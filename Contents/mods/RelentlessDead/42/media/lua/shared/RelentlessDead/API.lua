local Log = require "RelentlessDead/Log"
local Hooks = require "RelentlessDead/Hooks"

-- The public API for other mods, the global RelentlessDead.API, on every game. Rising runs on the
-- server and in single player, so only what is given there takes effect.
local API = { VERSION = 1 }

local EVENT = "OnRisingRose"

-- AddEvent returns the event if another mod has created it already, so whichever loads first,
-- handlers added to Events.OnRisingRose stay.
LuaEventManager.AddEvent(EVENT)

local function refuse(call, name, why)
    Log.error(call .. " " .. tostring(name) .. ": " .. why)
    return false, why
end

local function named(name)
    return type(name) == "string" and name ~= ""
end

-- phase: { rise = 0 to 100, wake = true or false, label = text or nil }, a function that returns
-- one (or nil to drive nothing) each time a zombie dies or corpses are checked, or nil to stop.
-- While a driver gives a phase, the RiseChance option rests. Returns true, or false and why.
function API.drive(name, phase)
    if not named(name) then
        return refuse("drive", name, "the name is not a text")
    end
    if type(phase) == "table" then
        local why = Hooks.invalid(phase)
        if why ~= nil then
            return refuse("drive", name, why)
        end
    elseif phase ~= nil and type(phase) ~= "function" then
        return refuse("drive", name, "the phase is not a table, a function or nil")
    end
    Hooks.drive(name, phase)
    Log.info("driver " .. name .. (phase == nil and " stopped" or " set"))
    return true
end

-- fn(zombie) runs at each death before the roll and returns why the zombie stays down (a text),
-- or nil. nil instead of fn removes it. Returns true, or false and why.
function API.addVeto(name, fn)
    if not named(name) then
        return refuse("addVeto", name, "the name is not a text")
    end
    if fn ~= nil and type(fn) ~= "function" then
        return refuse("addVeto", name, "fn is not a function or nil")
    end
    Hooks.veto(name, fn)
    return true
end

-- fn(body) runs on a corpse just before it rises. nil instead of fn removes it. Returns true, or
-- false and why.
function API.addBeforeRise(name, fn)
    if not named(name) then
        return refuse("addBeforeRise", name, "the name is not a text")
    end
    if fn ~= nil and type(fn) ~= "function" then
        return refuse("addBeforeRise", name, "fn is not a function or nil")
    end
    Hooks.before(name, fn)
    return true
end

-- Keeps the zombie corpse body down for good, and cancels a revival timer the game holds for it.
-- why goes to the log. Returns whether it was due to rise, or false and why.
function API.keepDown(body, why)
    if Hooks.keepDown == nil then
        return refuse("keepDown", body, "corpses are kept down on the server and in single player")
    end
    if not instanceof(body, "IsoDeadBody") then
        return refuse("keepDown", body, "it is not a corpse")
    end
    return Hooks.keepDown(body, why or "kept down by another mod")
end

-- Status lines, as the admin's Status writes them to the log; or false and why.
function API.status()
    if Hooks.report == nil then
        return refuse("status", nil, "rising runs on the server and in single player")
    end
    return Hooks.report().lines
end

RelentlessDead = RelentlessDead or {}
RelentlessDead.API = API

return API
