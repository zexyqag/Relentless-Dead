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
--
-- Registry: { next = the next id, low = no registered id is below it, count, entries = { [id] = {
--   x, y, z, due, died, misses } } }, ids given in registration order. x, y, z: the square the zombie
--   died on, or the one its corpse was put down on; due and died: world-age hours; misses: scans that
--   found the area loaded but neither the corpse nor someone dragging it.
-- Marker, the modData field RelentlessDead, which a corpse copies from its zombie and a zombie from
--   the corpse it rose from: { id, rises, due, died } on a registered corpse, { rises } on a risen
--   zombie. A corpse without an id never rises.
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

local UNDYING = "\\UndyingZombies"

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

-- ------------------------------------------------------------------ keeping down

-- Takes the marker off, ends its entry and cancels a revival timer the game holds for a zombie's
-- corpse, as Undying Zombies sets. A player's corpse keeps its timer: the game revives infected
-- players with it. Returns whether the corpse was due to rise.
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

-- ------------------------------------------------------------------ head hits

-- Zombie -> when a player's game reported a floor head hit on it, in milliseconds.
local reports = setmetatable({}, { __mode = "k" })
-- Online ID -> { at, x, y, z, id, zombie } of a registered zombie that just died, for a report that
-- comes after the death: the hit and the report travel in different packets.
local deaths = {}

local function headHit(z)
    local at = reports[z]
    reports[z] = nil
    return at ~= nil and getTimestampMs() - at <= WINDOW
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
    deaths[z:getOnlineID()] = { at = now, x = x, y = y, z = level, id = id, zombie = z }
end

-- ------------------------------------------------------------------ marking at death

-- Zombies whose death this life has handled: a zombie that burns to death fires the event twice.
-- The game reuses dead zombies and fires OnZombieCreate for each new life.
local handled = setmetatable({}, { __mode = "k" })

-- Why z stays down, or nil. rise: the rise in effect.
local function staysDown(z, m, rise)
    if z:getVariableBoolean("Bandit") then
        return "a Bandit"
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
    if z:isOnFire() and Settings.fireStaysDown() then
        return "it burned"
    end
    if Settings.headHitsStayDown() and headHit(z) then
        return "hit on the head on the floor"
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
    local x, y, level = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    local why = staysDown(z, m, Hooks.phase().rise)
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
    if isServer() and Settings.headHitsStayDown() then
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

-- Returns true if the corpse rose.
local function raise(id, body)
    local why = heldDown(body)
    if why ~= nil then
        keepDown(body, why)
        return false
    end
    body:setFakeDead(true)
    if not body:isFakeDead() then
        keepDown(body, "it can't play dead")
        Log.warnOnce("risers can't play dead", "a corpse on stairs, and every corpse while ZombieLore.DisableFakeDead"
            .. " is 3 (never), can't play dead, so it stays down instead of rising")
        return false
    end
    local square = body:getSquare()
    local data = body:getModData()
    local rises = data[Body.MARK].rises + 1
    data[Body.MARK] = { rises = rises }
    Hooks.beforeRise(body)
    local z = body:reanimate()
    remove(registry(), id)
    counts.rose = counts.rose + 1
    Log.info("corpse " .. id .. " rose at " .. place(square:getX(), square:getY(), square:getZ()) .. ", rise " .. rises
        .. " of this body")
    triggerEvent("OnRisingRose", z, rises)
    return true
end

local function scan()
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
        if tooOld(e.died, now, maxAge) then
            old[#old + 1] = id
        elseif wake and e.due <= now then
            due[#due + 1] = id
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
    local result = { at = now, due = #due, rose = 0, unloaded = 0, missed = 0, waiting = 0 }
    for _, id in ipairs(due) do
        if result.rose >= budget then
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
            if body ~= nil and raise(id, body) then
                result.rose = result.rose + 1
            end
        end
    end
    last = result
end

Events.OnZombieCreate.Add(function(z)
    handled[z] = nil
end)
Events.OnZombieDead.Add(died)
Events.EveryTenMinutes.Add(scan)

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
        if wanted[body:getObjectIDAsLong()] and body:isZombie() and not Body.finished(body) then
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
    if Settings.headHitsStayDown() and near(player, z:getX(), z:getY(), z:getZ()) then
        reports[z] = getTimestampMs()
    end
end

-- The same, from a player's game in multiplayer, by the zombie's online ID: it may have died here first.
local function headHitById(player, id)
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z:getOnlineID() == id and not z:isDead() then
            Rising.headHit(player, z)
            return
        end
    end
    local death = deaths[id]
    if death == nil or getTimestampMs() - death.at > WINDOW or not near(player, death.x + 0.5, death.y + 0.5, death.z)
        or not Settings.headHitsStayDown() then
        return
    end
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
        keepDown(body, "hit on the head on the floor")
    else
        remove(reg, death.id)
        counts.down = counts.down + 1
        Log.info("corpse " .. death.id .. " stays down: hit on the head on the floor")
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
        scanned = "last scan " .. stamp(last.at) .. ": " .. last.due .. " due, " .. last.rose .. " rose, " .. last.unloaded
            .. " not loaded, " .. last.missed .. " not found, " .. last.waiting .. " left for the next check"
    end
    local lines = {
        "Relentless Dead " .. getModInfoByID("RelentlessDead"):getModVersion(),
        "risers: rise " .. tostring(phase.rise) .. ", wake " .. string.lower(wake) .. ", set by " .. source .. "; " .. reg.count
            .. " corpses registered (at most " .. Settings.riserLimit() .. "), " .. due .. " due; " .. scanned,
        "this session: " .. counts.marked .. " marked to rise, " .. counts.down .. " kept down, " .. counts.rose .. " rose, "
            .. counts.finished .. " finished off, " .. counts.gone .. " gone, " .. counts.expired .. " too old, "
            .. counts.dropped .. " over the limit",
        Hooks.status(),
        "Zombie Dismemberment: " .. Body.dismembermentStatus(),
    }
    if getActivatedMods():contains(UNDYING) then
        lines[#lines + 1] = "warning: Undying Zombies is loaded too: its revival timers raise corpses whatever this mod's"
            .. " options say, except those this mod keeps down; use just one of the two"
    end
    return { text = "IGUI_RelentlessDead_Status", args = { reg.count, tostring(phase.rise), { key = "IGUI_RelentlessDead_" .. wake } },
        lines = lines }
end

Hooks.report = report

if getActivatedMods():contains(UNDYING) then
    Log.warn("Undying Zombies is loaded too: its revival timers raise corpses whatever this mod's options say, except"
        .. " those this mod keeps down; use just one of the two")
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Body.MODULE or type(args) ~= "table" then
        return
    end
    if command == "finishOff" then
        Rising.finishOff(player, args)
    elseif command == "headHit" then
        headHitById(player, args.id)
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
