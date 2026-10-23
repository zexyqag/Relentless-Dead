local Log = require "RelentlessDead/Log"

-- What every game knows of a zombie corpse: whether it was finished off, and the cuts Zombie
-- Dismemberment keeps in its modData, which a corpse copies from its zombie.
local Body = {}

Body.MODULE = "RelentlessDead"
-- Kept by the server, which never sends them: the registry of corpses that rise, and the risen zombies
-- whose rises it counts (see Rising).
Body.REGISTRY = "RelentlessDeadRisers"
Body.RISEN = "RelentlessDeadRisen"
-- modData fields: the marker of a corpse that rises (see Rising), and the flag every game sets on
-- a corpse finished off.
Body.MARK = "RelentlessDead"
Body.FINISHED = "RelentlessDeadFinished"

local DISMEMBERMENT = "\\ZombieDismembermentB42"
local ARMS = { ForeArm = true, UpperArm = true }
-- zombie.combat.HitReaction values of a shot in the head.
local SHOTS = { ShotHeadFwd = true, ShotHeadFwd02 = true, ShotHeadBwd = true }

local dismemberment = getActivatedMods():contains(DISMEMBERMENT)

function Body.headless(o)
    return o:hasModData() and o:getModData().ZD_Head == "Decapitated"
end

-- A Project A-Life NPC, alive, dying or dead: A-Life keeps the NPC's id in its modData from its
-- creation, and its corpse's owner from its death. A-Life's own death handler clears its other marks,
-- before or after this mod's as the mod list orders them, but keeps these.
function Body.npc(o)
    if not o:hasModData() then
        return false
    end
    local data = o:getModData()
    return type(data.ProjectALifeUID) == "string" or type(data.ProjectALifeCorpseOf) == "string"
end

-- Both arms cut off and a leg lost: Zombie Dismemberment keeps such a zombie on the floor.
function Body.crippled(o)
    if not o:hasModData() then
        return false
    end
    local data = o:getModData()
    return ARMS[data.ZD_L] == true and ARMS[data.ZD_R] == true and (data.ZD_LegL == "WholeLeg" or data.ZD_LegR == "WholeLeg")
end

-- A weapon that starts fires, as a molotov: its hits burn, whether its blast or a mod's burn damage.
function Body.incendiary(weapon)
    return weapon:getFireRange() > 0 or weapon:getFireStartingChance() > 0
end

-- Where a hit, as OnHitZombie gives it, struck the head, or nil: "shot", by a firearm's hit reaction,
-- which the shooter's game sets before the hit and a server takes from the hit it receives; "jaw", the
-- knife stab through the jaw, the attack's own reaction; "head", a melee hit whose spot the game
-- picked on the head, each game picking its own.
function Body.headStrike(z, wielder, part, weapon)
    -- A blast or a burn gets a spot rolled as a melee hit does, and the attacker's reaction from an
    -- earlier attack: neither is a blow to its head.
    if weapon == nil or weapon:isExplosive() or weapon:getExplosionRange() > 0 or Body.incendiary(weapon) then
        return nil
    end
    if weapon:isRanged() then
        if SHOTS[z:getHitReaction()] then
            return "shot"
        end
        return nil
    end
    if wielder:getVariableString("ZombieHitReaction") == "KnifeDeath" then
        return "jaw"
    end
    if part == BodyPartType.Head then
        return "head"
    end
    return nil
end

-- Whether Finish off is done with it: finished off, or its head is off, which every player sees.
function Body.finished(body)
    return Body.headless(body) or (body:hasModData() and body:getModData()[Body.FINISHED] == true)
end

local function runtime()
    if type(ZD_Runtime) == "table" and type(ZD_Runtime.corpse) == "function" then
        return ZD_Runtime
    end
    return nil
end

-- Whether Finish off takes the head off: Zombie Dismemberment is loaded with its corpse function,
-- and its own switches allow decapitation.
function Body.decapitates()
    local vars = SandboxVars.ZombieDismemberment
    return dismemberment and runtime() ~= nil and vars ~= nil and vars.Enabled == true and vars.EnableDecapitation == true
end

function Body.dismembermentStatus()
    if not dismemberment then
        return "not loaded"
    elseif runtime() == nil then
        return "loaded without ZD_Runtime.corpse, so Finish off leaves heads on"
    elseif Body.decapitates() then
        return "loaded, Finish off takes the head off"
    end
    return "loaded with decapitation off, so Finish off leaves heads on"
end

-- Marks the corpse finished off on this game. With head, it also takes the head off as Zombie
-- Dismemberment does, which removes hats, glasses and masks.
function Body.finish(body, head)
    local data = body:getModData()
    data[Body.FINISHED] = true
    local zd = runtime()
    if not head or zd == nil then
        return
    end
    data.ZD_Head = "Decapitated"
    local ok, err = pcall(zd.corpse, body)
    if not ok then
        Log.warnOnce("decapitation failed", "Zombie Dismemberment failed to take a head off (" .. tostring(err) .. ")")
    end
end

return Body
