require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"

local Settings = require "RelentlessDead/Settings"
local Body = require "RelentlessDead/Body"
local Hooks = require "RelentlessDead/Hooks"

-- What a player does to keep a corpse down: Finish off, and the head kills only its own game knows of.
-- Finish off is on every zombie corpse not yet finished off, so the menu doesn't show which ones would
-- rise, except Project A-Life's NPCs, which never rise here: A-Life's own Put down is for those that
-- turn. The server, or single player, keeps the corpses down and tells every player's game which were
-- finished off.

-- A timed action's time advances by the game's multiplier, 48 a second at normal speed.
local PER_SECOND = 48
-- Milliseconds this game waits for its copy of a zombie its player struck in the head to die.
local WAIT = 1000

-- The IDs of the zombie corpses on the square not yet finished off, those of ids only if given.
local function unfinished(square, ids)
    local wanted = nil
    if ids ~= nil then
        wanted = {}
        for _, id in ipairs(ids) do
            wanted[id] = true
        end
    end
    local list = {}
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if body:isZombie() and not Body.finished(body) and not Body.npc(body) then
            local id = body:getObjectIDAsLong()
            if wanted == nil or wanted[id] then
                list[#list + 1] = id
            end
        end
    end
    return list
end

-- The zombie corpse not yet finished off nearest the player on the squares of the objects clicked,
-- the first of equals, as the game picks the one corpse its own corpse options act on.
local function nearest(player, worldObjects)
    local best, seen = nil, {}
    for _, o in ipairs(worldObjects) do
        local square = o:getSquare()
        if square ~= nil and not seen[square] then
            seen[square] = true
            local bodies = square:getDeadBodys()
            for i = 0, bodies:size() - 1 do
                local body = bodies:get(i)
                if body:isZombie() and not Body.finished(body) and not Body.npc(body)
                    and (best == nil or best:DistToSquared(player) > body:DistToSquared(player)) then
                    best = body
                end
            end
        end
    end
    return best
end

local FinishOff = ISBaseTimedAction:derive("RelentlessDeadFinishOff")

function FinishOff:isValid()
    return #unfinished(self.square, self.ids) > 0
end

function FinishOff:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

-- Without a complete(), the game runs the whole action on the player's game alone, so the server
-- needs no copy of it and gets the corpses' IDs instead.
function FinishOff:perform()
    local square = self.square
    local args = { x = square:getX(), y = square:getY(), z = square:getZ(), ids = self.ids }
    if isClient() then
        sendClientCommand(self.character, Body.MODULE, "finishOff", args)
    else
        Hooks.rising.finishOff(self.character, args)
    end
    ISBaseTimedAction.perform(self)
end

function FinishOff:new(character, square, ids)
    local o = ISBaseTimedAction.new(self, character)
    o.square = square
    o.ids = ids
    o.maxTime = Settings.finishOffSeconds() * PER_SECOND
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end

local function finish(player, square, ids)
    if luautils.walkAdj(player, square) then
        ISTimedActionQueue.add(FinishOff:new(player, square, ids))
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test or not Settings.finishOff() then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if player == nil then
        return
    end
    local body = nearest(player, worldObjects)
    if body == nil then
        return
    end
    local square = body:getSquare()
    local ids = unfinished(square, nil)
    if #ids == 1 then
        context:addOption(getText("ContextMenu_RelentlessDead_FinishOff"), player, finish, square, ids)
    else
        context:addOption(getText("ContextMenu_RelentlessDead_FinishOffAll", #ids), player, finish, square, ids)
    end
end)

-- Every game that learns of a hit fires this, but only the attacker's own game knows where it landed.
Events.OnWeaponHitCharacter.Add(function(wielder, target, weapon, damage)
    if not Settings.headKillsStayDown() or not instanceof(target, "IsoZombie") or not instanceof(wielder, "IsoPlayer")
        or not wielder:isLocalPlayer() or weapon:isRanged() or target:getHitHeadWhileOnFloor() <= 0 then
        return
    end
    if isClient() then
        sendClientCommand(wielder, Body.MODULE, "headHit", { id = target:getOnlineID() })
    else
        Hooks.rising.headHit(wielder, target)
    end
end)

-- In multiplayer, a shot in the head or the knife stab through the jaw that killed this game's copy of
-- the zombie is reported by its online ID: the server may not know where the blow landed, as when a
-- mod resolves shots on the shooter's game alone. A melee hit's spot is each game's own pick, so the
-- server keeps to its own.
if isClient() then
    local struck = {}
    Events.OnHitZombie.Add(function(z, wielder, part, weapon)
        -- Another player's hit is that player's game's to report: the game sends nothing for a player not its own.
        if not Settings.headKillsStayDown() or not instanceof(wielder, "IsoPlayer") then
            return
        end
        local head = Body.headStrike(z, wielder, part, weapon)
        if head == "shot" or head == "jaw" then
            struck[#struck + 1] = { zombie = z, player = wielder, at = getTimestampMs() }
        end
    end)
    -- The hit applies its damage after the event: by the next tick, a copy it killed is dead.
    Events.OnTick.Add(function()
        if #struck == 0 then
            return
        end
        local now, keep = getTimestampMs(), {}
        for _, s in ipairs(struck) do
            if now - s.at <= WAIT then
                if s.zombie:isDead() then
                    sendClientCommand(s.player, Body.MODULE, "headKill", { id = s.zombie:getOnlineID() })
                else
                    keep[#keep + 1] = s
                end
            end
        end
        struck = keep
    end)
end

-- The server finished off corpses: this game's copies of those it has loaded are finished off too,
-- so its menu leaves them out, and lose their heads as the server's did.
if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= Body.MODULE or command ~= "finished" or type(args) ~= "table" or type(args.ids) ~= "table" then
            return
        end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if square == nil then
            return
        end
        local wanted = {}
        for _, id in ipairs(args.ids) do
            wanted[id] = true
        end
        local bodies = square:getDeadBodys()
        for i = 0, bodies:size() - 1 do
            local body = bodies:get(i)
            if wanted[body:getObjectIDAsLong()] then
                Body.finish(body, args.head == true)
            end
        end
    end)
end
