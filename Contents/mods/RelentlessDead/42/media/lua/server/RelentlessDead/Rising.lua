if isClient() then return end

require "TimedActions/ISBurnCorpseAction"

local Log = require "RelentlessDead/Log"
local Settings = require "RelentlessDead/Settings"
local Body = require "RelentlessDead/Body"
local Hooks = require "RelentlessDead/Hooks"
-- Creates OnRisingRose.
require "RelentlessDead/API"

-- Killed zombies that get back up. At its death a zombie is marked to rise by the rise in effect;
-- while wake is on, its corpse rises once due, as a corpse playing dead does, so the zombie stays
-- one of the population. Rise and wake are a driving mod's (see API), else RiseChance and always.
-- With RiseWarning on, a corpse a check lets rise groans, and gets up RiseWarningMinutes later.
--
-- Registry: { next = the next id, low = no registered id is below it, count, entries = { [id] = {
--   x, y, z, due, died, misses, rising } } }, ids given in registration order. x, y, z: the square the
--   zombie died on, or the one its corpse was put down on; due and died: world-age hours; misses: scans
--   that found the area loaded but neither the corpse nor someone dragging it; rising: the world-age
--   hour a corpse that groaned gets up at.
-- Risen: { count, entries = { [id] = { outfit, rises, x, y, z, seen } } }, the risen zombies by the id
--   of the corpse each rose from, with its outfit and where a check last saw it. The game keeps no
--   modData of a zombie it unloads, so one it loads again in that outfit near there is taken for it.
-- Marker, the modData field RelentlessDead, which a corpse copies from its zombie and a zombie from
--   the corpse it rose from: { id, rises, due, died } on a registered corpse, { rises, riser } on a
--   risen zombie, riser being its id in Risen. A corpse without an id never rises.
local Rising = {}

-- Scans that miss a corpse before its entry is dropped: a corpse being dragged is a zombie, not a
-- corpse, until it is put down.
local MISSES = 3
-- Tiles around the square of an entry, and the level below, searched for a corpse that isn't on it: a
-- corpse can slide or fall while the zombie dies.
local SEARCH = 3
-- Searches around entries a scan may make per rise RisesPerScan allows; the other entries wait.
local SEARCHES = 5
-- Tiles a player may be from a corpse to finish it off, or from a zombie to report a head hit.
local REACH = 3
-- Milliseconds between a head-hit report and the death it belongs to, in either order.
local WINDOW = 5000
-- Milliseconds from a hit to the death it causes, which the game runs within the hit.
local MOMENT = 1000
-- Tiles from where a check last saw a risen zombie within which a zombie loaded in its outfit is it.
local SEEK = 20
local MINUTE = 1 / 60
local HEADS = { shot = "shot in the head", jaw = "stabbed through the jaw", head = "hit on the head" }
-- PersistentOutfits.NO_HAT_BIT, which the game sets in the outfit ID once the hat has fallen off.
local HAT = 32768
local VOICES = { "A", "B", "C" }

-- Since this game started, for the status.
local counts = { marked = 0, down = 0, rose = 0, gone = 0, expired = 0, dropped = 0, finished = 0 }
local last = nil

local function hours()
    return getGameTime():getWorldAgeHours()
end

-- "YYYY-MM-DD HH:MM" of the world-age hour h.
local function stamp(h)
    local time = getGameTime()
    local year, month, day = time:getYear(), time:getMonth(), time:getDay() + 1
    local minutes = math.floor((time:getTimeOfDay() + h - time:getWorldAgeHours()) * 60 + 0.5)
    while minutes < 0 do
        minutes = minutes + 24 * 60
        day = day - 1
        if day < 1 then
            month = month - 1
            if month < 0 then
                month, year = 11, year - 1
            end
            day = time:daysInMonth(year, month)
        end
    end
    while minutes >= 24 * 60 do
        minutes = minutes - 24 * 60
        day = day + 1
        if day > time:daysInMonth(year, month) then
            day, month = 1, month + 1
            if month > 11 then
                month, year = 0, year + 1
            end
        end
    end
    return string.format("%d-%02d-%02d %02d:%02d", year, month + 1, day, math.floor(minutes / 60), minutes % 60)
end

local function registry()
    local reg = ModData.getOrCreate(Body.REGISTRY)
    if reg.entries == nil then
        reg.next, reg.low, reg.count, reg.entries = 1, 1, 0, {}
    end
    return reg
end

local function remove(reg, id)
    if reg.entries[id] ~= nil then
        reg.entries[id] = nil
        reg.count = reg.count - 1
    end
end

-- Drops the oldest entries above RiserLimit.
local function trim(reg)
    local limit = Settings.riserLimit()
    while reg.count > limit and reg.low < reg.next do
        if reg.entries[reg.low] ~= nil then
            remove(reg, reg.low)
            counts.dropped = counts.dropped + 1
        end
        reg.low = reg.low + 1
    end
end

local function add(reg, id, entry)
    if reg.entries[id] == nil then
        reg.count = reg.count + 1
    end
    reg.entries[id] = entry
    trim(reg)
end

local function tooOld(died, now, maxAge)
    return maxAge > 0 and now - died > maxAge
end

local function marker(o)
    if not o:hasModData() then
        return nil
    end
    local m = o:getModData()[Body.MARK]
    if type(m) ~= "table" then
        return nil
    end
    return m
end

local function marked(o, id)
    local m = marker(o)
    return m ~= nil and m.id == id
end

local function near(player, x, y, z)
    local dx, dy = player:getX() - x, player:getY() - y
    return dx * dx + dy * dy <= REACH * REACH and math.floor(player:getZ()) == math.floor(z)
end

local function place(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

-- ------------------------------------------------------------------ risen zombies

local function risen()
    local book = ModData.getOrCreate(Body.RISEN)
    if book.entries == nil then
        book.count, book.entries = 0, {}
    end
    return book
end

-- The outfit ID without the hat bit. Kahlua's % keeps the sign of a negative ID.
local function outfitOf(z)
    local id = z:getPersistentOutfitID()
    if id - math.floor(id / 65536) * 65536 >= HAT then
        return id - HAT
    end
    return id
end

-- Risen id -> its zombie, once this game has had it loaded.
local here = {}
-- Outfit -> { [risen id] = true }, made from Risen when first needed.
local outfits = nil

local function byOutfit(book)
    if outfits == nil then
        outfits = {}
        for id, r in pairs(book.entries) do
            outfits[r.outfit] = outfits[r.outfit] or {}
            outfits[r.outfit][id] = true
        end
    end
    return outfits
end

local function index(book, id, outfit)
    local all = byOutfit(book)
    all[outfit] = all[outfit] or {}
    all[outfit][id] = true
end

local function unindex(book, id)
    local ids = byOutfit(book)[book.entries[id].outfit]
    if ids ~= nil then
        ids[id] = nil
    end
end

local function see(book, id, z)
    local r = book.entries[id]
    local outfit = outfitOf(z)
    if outfit ~= r.outfit then
        unindex(book, id)
        r.outfit = outfit
        index(book, id, outfit)
    end
    r.x, r.y, r.z, r.seen = z:getX(), z:getY(), z:getZ(), hours()
    here[id] = z
end

-- z just rose from the corpse id, its rises-th rise.
local function remember(id, z, rises)
    local book = risen()
    local outfit = outfitOf(z)
    book.entries[id] = { outfit = outfit, rises = rises }
    book.count = book.count + 1
    index(book, id, outfit)
    see(book, id, z)
end

local function forget(id)
    local book = risen()
    if book.entries[id] == nil then
        return
    end
    unindex(book, id)
    book.entries[id] = nil
    book.count = book.count - 1
    here[id] = nil
end

-- Whether the risen zombie id is in the world now. Once the game has unloaded it, its object has no
-- square, or has been reused, with its modData wiped.
local function loaded(id)
    local old = here[id]
    if old == nil or old:getCurrentSquare() == nil then
        return false
    end
    local m = marker(old)
    return m ~= nil and m.riser == id
end

-- A zombie the game creates, from its population or a save, takes up the count of the risen zombie
-- whose outfit it has, if it is within SEEK tiles of where a check last saw that one.
local function claim(z)
    local book = risen()
    if book.count == 0 then
        return
    end
    local ids = byOutfit(book)[outfitOf(z)]
    if ids == nil then
        return
    end
    local best, distance = nil, nil
    for id in pairs(ids) do
        local r = book.entries[id]
        local dx, dy = r.x - z:getX(), r.y - z:getY()
        local d = dx * dx + dy * dy
        if d <= SEEK * SEEK and not loaded(id) and (best == nil or d < distance or (d == distance and id < best)) then
            best, distance = id, d
        end
    end
    if best == nil then
        return
    end
    local r = book.entries[best]
    z:getModData()[Body.MARK] = { rises = r.rises, riser = best }
    see(book, best, z)
    Log.info("risen zombie " .. best .. " is back at " .. place(z:getX(), z:getY(), z:getZ()) .. " with " .. r.rises .. " rises")
end

-- Where the loaded risen zombies are, for when the game unloads them; above RiserLimit, those not
-- seen the longest are forgotten.
local function track()
    local book = risen()
    if book.count == 0 then
        return
    end
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        local m = marker(z)
        if m ~= nil and m.riser ~= nil and book.entries[m.riser] ~= nil then
            see(book, m.riser, z)
        end
    end
    local extra = book.count - Settings.riserLimit()
    if extra <= 0 then
        return
    end
    local ids = {}
    for id in pairs(book.entries) do
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
        local sa, sb = book.entries[a].seen, book.entries[b].seen
        return sa < sb or (sa == sb and a < b)
    end)
    for i = 1, extra do
        forget(ids[i])
    end
    Log.info(extra .. " risen zombies not seen the longest are forgotten: more than RiserLimit")
end

-- ------------------------------------------------------------------ keeping down

-- Takes the marker off, ends its entry and cancels a revival timer the game holds for a zombie's
-- corpse, whoever set it. A player's corpse keeps its timer: the game revives infected players with
-- it. Returns whether the corpse was due to rise.
local function unmark(body, why)
    local m = marker(body)
    local rising = false
    if m ~= nil and m.id ~= nil then
        body:getModData()[Body.MARK] = nil
        remove(registry(), m.id)
        rising = true
        Log.info("corpse " .. m.id .. " stays down: " .. why)
    end
    if body:isZombie() and body:getReanimateTime() > 0 then
        body:setReanimateTime(-1)
        rising = true
        Log.info("the game's revival timer of the corpse at " .. place(body:getX(), body:getY(), body:getZ())
            .. " is cancelled: " .. why)
    end
    return rising
end

local function keepDown(body, why)
    local rising = unmark(body, why)
    if rising then
        counts.down = counts.down + 1
    end
    return rising
end

Hooks.keepDown = keepDown

-- A burned corpse stays down when the burn is done, even where the server lights no fire (no fire
-- allowed, water, a safehouse) and in the seconds before the fire takes it. complete() runs on the
-- server and in single player.
local burnComplete = ISBurnCorpseAction.complete
function ISBurnCorpseAction:complete()
    keepDown(self.corpse, "burned")
    return burnComplete(self)
end

-- ------------------------------------------------------------------ head kills

-- Zombie -> when a player's game reported a floor head hit on it, in milliseconds.
local reports = setmetatable({}, { __mode = "k" })
-- Zombie -> { by, at } of a player whose game reported that its player killed it with a blow to the
-- head, before the hit reached this game.
local claims = setmetatable({}, { __mode = "k" })
-- Online ID -> { at, x, y, z, id, zombie, by } of a registered zombie that just died, for a report that
-- comes after the death: the hit and the report travel in different packets.
local deaths = {}
-- The last zombie hit on this game: { zombie, by, at, head, fire }. The game fires OnHitZombie as a
-- hit starts and, when the hit kills, OnZombieDead within the same hit.
local strike = nil

local function headHit(z)
    local at = reports[z]
    reports[z] = nil
    return at ~= nil and getTimestampMs() - at <= WINDOW
end

local function claimed(z)
    local c = claims[z]
    claims[z] = nil
    return c ~= nil and c.by == z:getAttackedBy() and getTimestampMs() - c.at <= WINDOW
end

local function rememberDeath(z, id, x, y, level)
    local now = getTimestampMs()
    local old = {}
    for key, death in pairs(deaths) do
        if now - death.at > WINDOW then
            old[#old + 1] = key
        end
    end
    for _, key in ipairs(old) do
        deaths[key] = nil
    end
    deaths[z:getOnlineID()] = { at = now, x = x, y = y, z = level, id = id, zombie = z, by = z:getAttackedBy() }
end

-- A weapon that starts fires, as a molotov does: its blast can kill before the zombie burns.
local function incendiary(weapon)
    return weapon ~= nil and (weapon:getFireRange() > 0 or weapon:getFireStartingChance() > 0)
end

Events.OnHitZombie.Add(function(z, wielder, part, weapon)
    strike = { zombie = z, by = wielder, at = getTimestampMs(), head = Body.headStrike(z, wielder, part, weapon),
        fire = incendiary(weapon) }
end)

-- The hit that killed z, dying now, or nil. A death without a hit, as by fire, has no attacker.
local function killing(z)
    local s = strike
    if s == nil or s.zombie ~= z then
        return nil
    end
    strike = nil
    if s.by ~= z:getAttackedBy() or getTimestampMs() - s.at > MOMENT then
        return nil
    end
    return s
end

-- Whether z dies of fire: burning, on a square with a fire, or by the blast of a weapon that starts fires.
local function burned(z, s)
    if z:isOnFire() or (s ~= nil and s.fire) then
        return true
    end
    local square = getCell():getGridSquare(z:getX(), z:getY(), z:getZ())
    return square ~= nil and square:haveFire()
end

-- ------------------------------------------------------------------ marking at death

-- Zombies whose death this life has handled: a zombie that burns to death fires the event twice.
-- The game reuses dead zombies and fires OnZombieCreate for each new life.
local handled = setmetatable({}, { __mode = "k" })

-- Why z stays down, or nil. rise: the rise in effect; s: the hit that killed it, or nil.
local function staysDown(z, m, rise, s)
    if z:getVariableBoolean("Bandit") then
        return "a Bandit"
    end
    if Body.npc(z) then
        return "an A-Life NPC"
    end
    if Body.headless(z) then
        return "its head is off"
    end
    if Body.crippled(z) then
        return "it has no arms and a leg off"
    end
    local vetoed = Hooks.vetoed(z)
    if vetoed ~= nil then
        return vetoed
    end
    if z:isReanimatedPlayer() and not Settings.risePlayers() then
        return "a player's zombie"
    end
    if Settings.fireStaysDown() and burned(z, s) then
        return "it burned"
    end
    if Settings.headKillsStayDown() then
        if s ~= nil and s.head ~= nil then
            return HEADS[s.head]
        end
        if claimed(z) then
            return "a blow to the head, as its attacker's game saw it"
        end
        if headHit(z) then
            return "hit on the head on the floor"
        end
    end
    local max = Settings.maxRises()
    if max > 0 and m ~= nil and m.rises >= max then
        return "it rose " .. m.rises .. " times"
    end
    if rise <= 0 then
        return "rise 0"
    end
    if rise < 100 then
        local rolled = ZombRandFloat(0, 100)
        if rolled >= rise then
            return string.format("rolled %.1f, not below rise %s", rolled, tostring(rise))
        end
    end
    return nil
end

local function delay()
    local low, high = Settings.riseDelay()
    if high > low then
        return ZombRandFloat(low, high)
    end
    return low
end

-- A dragged corpse is a zombie until it is put down, and dies again then: its new corpse takes the
-- marker, and the entry moves to where it lies, made again from the marker if scans missed it. A
-- corpse the limit or its age dropped stays down.
local function dropped(z, m)
    if m == nil or m.id == nil then
        return
    end
    local reg = registry()
    local entry = reg.entries[m.id]
    local x, y, level = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    if entry == nil then
        local why = nil
        if m.id < reg.low then
            why = "it is older than RiserLimit keeps"
        elseif tooOld(m.died, hours(), Settings.riseMaxAgeHours()) then
            why = "it is older than RiseMaxAgeHours"
        end
        if why ~= nil then
            z:getModData()[Body.MARK] = nil
            Log.info("corpse " .. m.id .. " put down at " .. place(x, y, level) .. " stays down: " .. why)
            return
        end
        entry = { due = m.due, died = m.died }
        add(reg, m.id, entry)
    end
    entry.x, entry.y, entry.z, entry.misses = x, y, level, 0
    Log.info("corpse " .. m.id .. " put down at " .. place(x, y, level))
end

local function died(z)
    if handled[z] then
        return
    end
    handled[z] = true
    local m = marker(z)
    if z:isReanimatedForGrappleOnly() then
        dropped(z, m)
        return
    end
    if m ~= nil and m.riser ~= nil then
        forget(m.riser)
    end
    local x, y, level = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    local why = staysDown(z, m, Hooks.phase().rise, killing(z))
    if why ~= nil then
        if m ~= nil then
            z:getModData()[Body.MARK] = nil
        end
        counts.down = counts.down + 1
        Log.info("zombie killed at " .. place(x, y, level) .. " stays down: " .. why)
        return
    end
    local reg = registry()
    local id = reg.next
    reg.next = id + 1
    local now = hours()
    local due = now + delay()
    local rises = 0
    if m ~= nil then
        rises = m.rises
    end
    z:getModData()[Body.MARK] = { id = id, rises = rises, due = due, died = now }
    add(reg, id, { x = x, y = y, z = level, due = due, died = now, misses = 0 })
    counts.marked = counts.marked + 1
    if isServer() and Settings.headKillsStayDown() then
        rememberDeath(z, id, x, y, level)
    end
    Log.info("zombie killed at " .. place(x, y, level) .. " marked to rise as corpse " .. id .. " from " .. stamp(due))
end

-- ------------------------------------------------------------------ rising

-- The corpse marked id on the square, or nil.
local function holder(square, id)
    if square == nil then
        return nil
    end
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if marked(body, id) then
            return body
        end
    end
    return nil
end

-- The corpse marked id anywhere in the search area of the entry e, or nil.
local function search(cell, e, id)
    for level = e.z, e.z - 1, -1 do
        for dx = -SEARCH, SEARCH do
            for dy = -SEARCH, SEARCH do
                local body = holder(cell:getGridSquare(e.x + dx, e.y + dy, level), id)
                if body ~= nil then
                    return body
                end
            end
        end
    end
    return nil
end

-- Marker id -> the zombie that is that corpse while someone drags it.
local function carriers()
    local out = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z:isReanimatedForGrappleOnly() then
            local m = marker(z)
            if m ~= nil and m.id ~= nil then
                out[m.id] = z
            end
        end
    end
    return out
end

-- Whether the dragged corpse z, or nil, is in the search area of the entry e.
local function nearby(z, e)
    if z == nil then
        return false
    end
    local level = math.floor(z:getZ())
    return math.abs(math.floor(z:getX()) - e.x) <= SEARCH and math.abs(math.floor(z:getY()) - e.y) <= SEARCH
        and (level == e.z or level == e.z - 1)
end

-- Why the corpse stays down now, or nil.
local function heldDown(body)
    if not Settings.riseInSafehouses() and SafeHouse.getSafeHouse(body:getSquare()) ~= nil then
        return "it lies in a safehouse"
    end
    if Body.headless(body) then
        return "its head is off"
    end
    if Body.crippled(body) then
        return "it has no arms and a leg off"
    end
    return nil
end

local function cantPlayDead(body)
    keepDown(body, "it can't play dead")
    Log.warnOnce("risers can't play dead", "a corpse on stairs, and every corpse while ZombieLore.DisableFakeDead"
        .. " is 3 (never), can't play dead, so it stays down instead of rising")
end

-- Returns true if the corpse rose.
local function raise(id, body)
    local why = heldDown(body)
    if why ~= nil then
        keepDown(body, why)
        return false
    end
    body:setFakeDead(true)
    if not body:isFakeDead() then
        cantPlayDead(body)
        return false
    end
    local square = body:getSquare()
    local data = body:getModData()
    local mark = data[Body.MARK]
    local rises = mark.rises + 1
    data[Body.MARK] = { rises = rises, riser = id }
    Hooks.beforeRise(body)
    local z = body:reanimate()
    if z == nil then
        data[Body.MARK] = mark
        body:setFakeDead(false)
        Log.warnOnce("no zombie ID", "the server has no zombie ID left, so corpses wait to rise")
        return false
    end
    remove(registry(), id)
    remember(id, z, rises)
    counts.rose = counts.rose + 1
    Log.info("corpse " .. id .. " rose at " .. place(square:getX(), square:getY(), square:getZ()) .. ", rise " .. rises
        .. " of this body")
    triggerEvent("OnRisingRose", z, rises)
    return true
end

-- ------------------------------------------------------------------ the warning before rising

-- Ids of the corpses that groaned and wait to get up, made from the registry when first needed.
local groaned = nil

local function waiting()
    if groaned == nil then
        groaned = {}
        for id, e in pairs(registry().entries) do
            if e.rising ~= nil then
                groaned[id] = true
            end
        end
    end
    return groaned
end

-- A zombie's voice from the corpse. A server sends it to every player's game that has the corpse's
-- area loaded or is within 10 tiles of it, and each plays it there.
local function groan(id, body)
    local voice = "MaleZombieVoice"
    if body:isFemale() then
        voice = "FemaleZombieVoice"
    end
    voice = voice .. VOICES[id % 3 + 1]
    local square = body:getSquare()
    if isServer() then
        playServerSound(voice, square)
    else
        square:playSound(voice)
    end
end

-- The corpse rises now, or with RiseWarning on groans and gets up RiseWarningMinutes later. Returns
-- true if it rose or groaned.
local function start(id, e, body, now)
    if not Settings.riseWarning() then
        return raise(id, body)
    end
    local why = heldDown(body)
    if why ~= nil then
        keepDown(body, why)
        return false
    end
    local was = body:isFakeDead()
    body:setFakeDead(true)
    local plays = body:isFakeDead()
    body:setFakeDead(was)
    if not plays then
        cantPlayDead(body)
        return false
    end
    groan(id, body)
    e.rising = now + Settings.riseWarningMinutes() * MINUTE
    waiting()[id] = true
    Log.info("corpse " .. id .. " groans at " .. place(body:getX(), body:getY(), body:getZ()) .. " and gets up at "
        .. stamp(e.rising))
    return true
end

-- Each in-game minute, the corpses that groaned get up once their time has come, wherever they lie
-- now. One that isn't found then (being dragged, or its area unloaded) waits for a check, and groans
-- again before it gets up.
local function getUp()
    local list = waiting()
    local reg = registry()
    local now = hours()
    local stale, ready = {}, {}
    for id in pairs(list) do
        local e = reg.entries[id]
        if e == nil or e.rising == nil then
            stale[#stale + 1] = id
        elseif e.rising < now + MINUTE / 2 then
            ready[#ready + 1] = id
        end
    end
    for _, id in ipairs(stale) do
        list[id] = nil
    end
    table.sort(ready)
    local cell = getCell()
    for _, id in ipairs(ready) do
        list[id] = nil
        -- A function run by an earlier rise may have kept this corpse down.
        local e = reg.entries[id]
        if e ~= nil then
            e.rising = nil
            local body = nil
            if cell:getGridSquare(e.x, e.y, 0) ~= nil then
                body = holder(cell:getGridSquare(e.x, e.y, e.z), id) or search(cell, e, id)
            end
            if body == nil then
                Log.info("corpse " .. id .. " isn't there to get up, so it waits for a check")
            else
                raise(id, body)
            end
        end
    end
end

local function scan()
    track()
    local reg = registry()
    if reg.count == 0 then
        return
    end
    trim(reg)
    local wake = Hooks.phase().wake
    local maxAge = Settings.riseMaxAgeHours()
    if not wake and maxAge == 0 then
        return
    end
    local now = hours()
    local old, due = {}, {}
    for id, e in pairs(reg.entries) do
        if e.rising == nil then
            if tooOld(e.died, now, maxAge) then
                old[#old + 1] = id
            elseif wake and e.due <= now then
                due[#due + 1] = id
            end
        end
    end
    for _, id in ipairs(old) do
        remove(reg, id)
        counts.expired = counts.expired + 1
    end
    table.sort(due)
    local cell = getCell()
    local budget = Settings.risesPerScan()
    local searches = SEARCHES * budget
    local dragging = nil
    local result = { at = now, due = #due, up = 0, unloaded = 0, missed = 0, waiting = 0 }
    for _, id in ipairs(due) do
        if result.up >= budget then
            break
        end
        local e = reg.entries[id]
        -- Not loaded, which doesn't use up the scan. A loaded chunk has every square of its ground level,
        -- while the square of the entry may not exist.
        if cell:getGridSquare(e.x, e.y, 0) == nil then
            result.unloaded = result.unloaded + 1
        else
            local body = holder(cell:getGridSquare(e.x, e.y, e.z), id)
            if body == nil and searches == 0 then
                result.waiting = result.waiting + 1
            elseif body == nil then
                dragging = dragging or carriers()
                if not nearby(dragging[id], e) then
                    searches = searches - 1
                    body = search(cell, e, id)
                    if body == nil then
                        result.missed = result.missed + 1
                        e.misses = e.misses + 1
                        if e.misses >= MISSES then
                            remove(reg, id)
                            counts.gone = counts.gone + 1
                            Log.info("corpse " .. id .. " is gone: burned, removed or carried off")
                        end
                    end
                end
            end
            if body ~= nil and start(id, e, body, now) then
                result.up = result.up + 1
            end
        end
    end
    last = result
end

Events.OnZombieCreate.Add(function(z)
    handled[z] = nil
    claim(z)
end)
Events.OnZombieDead.Add(died)
Events.EveryTenMinutes.Add(scan)
Events.EveryOneMinute.Add(getUp)
-- Single player saves its zombies where they stand: their places are noted first.
Events.OnSave.Add(track)

-- ------------------------------------------------------------------ finish off and head hits

-- args: { x, y, z, ids = { object IDs of corpses on that square } }: the game's own corpse ID, which
-- every game shares. Each zombie corpse there not yet finished off is finished off, and every player's
-- game is told. Returns how many of them were marked to rise.
function Rising.finishOff(player, args)
    if not Settings.finishOff() or type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number"
        or type(args.ids) ~= "table" then
        return 0
    end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if square == nil or not near(player, args.x + 0.5, args.y + 0.5, args.z) then
        Log.info(player:getUsername() .. " is too far from " .. place(args.x, args.y, args.z) .. " to finish off corpses there")
        return 0
    end
    local wanted = {}
    for _, id in ipairs(args.ids) do
        wanted[id] = true
    end
    local head = Body.decapitates()
    local done, n = {}, 0
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if wanted[body:getObjectIDAsLong()] and body:isZombie() and not Body.finished(body) and not Body.npc(body) then
            if unmark(body, "finished off") then
                n = n + 1
            end
            Body.finish(body, head)
            done[#done + 1] = body:getObjectIDAsLong()
        end
    end
    if isServer() and #done > 0 then
        sendServerCommand(Body.MODULE, "finished", { x = square:getX(), y = square:getY(), z = square:getZ(), ids = done, head = head })
    end
    counts.finished = counts.finished + n
    Log.info(player:getUsername() .. " finished off " .. #done .. " corpses at " .. place(args.x, args.y, args.z) .. ", " .. n
        .. " of them due to rise")
    return n
end

-- A player's game saw its own player hit z on the head while z lay on the floor.
function Rising.headHit(player, z)
    if Settings.headKillsStayDown() and near(player, z:getX(), z:getY(), z:getZ()) then
        reports[z] = getTimestampMs()
    end
end

-- The zombie that has the online ID id here, alive, or nil.
local function alive(id)
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z:getOnlineID() == id and not z:isDead() then
            return z
        end
    end
    return nil
end

-- A late report keeps down the corpse of a registered zombie that died here.
local function downAfterDeath(id, death, why)
    deaths[id] = nil
    -- Its corpse may come later, with a copy of its modData.
    death.zombie:getModData()[Body.MARK] = nil
    local reg = registry()
    local e = reg.entries[death.id]
    if e == nil then
        return
    end
    local body = search(getCell(), e, death.id)
    if body ~= nil then
        keepDown(body, why)
    else
        remove(reg, death.id)
        counts.down = counts.down + 1
        Log.info("corpse " .. death.id .. " stays down: " .. why)
    end
end

local function late(id)
    local death = deaths[id]
    if death == nil or getTimestampMs() - death.at > WINDOW or not Settings.headKillsStayDown() then
        return nil
    end
    return death
end

-- A floor head hit, from a player's game in multiplayer, by the zombie's online ID: it may have died
-- here first.
local function headHitById(player, id)
    local z = alive(id)
    if z ~= nil then
        Rising.headHit(player, z)
        return
    end
    local death = late(id)
    if death ~= nil and near(player, death.x + 0.5, death.y + 0.5, death.z) then
        downAfterDeath(id, death, "hit on the head on the floor")
    end
end

-- A player's game saw its player kill the zombie with a shot in the head or the knife stab through the
-- jaw: this game may not know where the blow landed. It counts only if that player killed it here.
local function headKillById(player, id)
    if not Settings.headKillsStayDown() then
        return
    end
    local z = alive(id)
    if z ~= nil then
        claims[z] = { by = player, at = getTimestampMs() }
        return
    end
    local death = late(id)
    if death ~= nil and death.by == player then
        downAfterDeath(id, death, "a blow to the head, as its attacker's game saw it")
    end
end

-- ------------------------------------------------------------------ status

local function allowed(player)
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions)
end

-- The admin's Status: { text, args, lines } for the player's screen and the log.
local function report()
    local reg = registry()
    local now = hours()
    local due = 0
    for _, e in pairs(reg.entries) do
        if e.due <= now then
            due = due + 1
        end
    end
    local phase = Hooks.phase()
    local source = "its own options"
    if phase.driver ~= nil then
        source = phase.driver
        if phase.label ~= nil then
            source = source .. " (" .. phase.label .. ")"
        end
    end
    local wake = "Off"
    if phase.wake then
        wake = "On"
    end
    local scanned = "no scan yet"
    if last ~= nil then
        scanned = "last scan " .. stamp(last.at) .. ": " .. last.due .. " due, " .. last.up .. " getting up, " .. last.unloaded
            .. " not loaded, " .. last.missed .. " not found, " .. last.waiting .. " left for the next check"
    end
    local lines = {
        "Relentless Dead " .. getModInfoByID("RelentlessDead"):getModVersion(),
        "risers: rise " .. tostring(phase.rise) .. ", wake " .. string.lower(wake) .. ", set by " .. source .. "; " .. reg.count
            .. " corpses registered (at most " .. Settings.riserLimit() .. "), " .. due .. " due; " .. risen().count
            .. " risen zombies counted; " .. scanned,
        "this session: " .. counts.marked .. " marked to rise, " .. counts.down .. " kept down, " .. counts.rose .. " rose, "
            .. counts.finished .. " finished off, " .. counts.gone .. " gone, " .. counts.expired .. " too old, "
            .. counts.dropped .. " over the limit",
        Hooks.status(),
        "Zombie Dismemberment: " .. Body.dismembermentStatus(),
    }
    return { text = "IGUI_RelentlessDead_Status", args = { reg.count, tostring(phase.rise), { key = "IGUI_RelentlessDead_" .. wake } },
        lines = lines }
end

Hooks.report = report

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Body.MODULE or type(args) ~= "table" then
        return
    end
    if command == "finishOff" then
        Rising.finishOff(player, args)
    elseif command == "headHit" then
        headHitById(player, args.id)
    elseif command == "headKill" then
        headKillById(player, args.id)
    elseif command == "status" then
        local reply
        if allowed(player) then
            reply = report()
            for _, line in ipairs(reply.lines) do
                print("[RelentlessDead] " .. line)
            end
        else
            Log.warn(player:getUsername() .. " asked for the status without the sandbox options capability")
            reply = { text = "IGUI_RelentlessDead_Denied" }
        end
        reply.player = args.player
        sendServerCommand(player, Body.MODULE, "status", reply)
    end
end)

-- Single player has no server to send to: the corpse actions call these directly.
Hooks.rising = Rising

return Rising
