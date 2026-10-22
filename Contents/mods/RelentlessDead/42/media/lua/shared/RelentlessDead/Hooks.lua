local Log = require "RelentlessDead/Log"
local Settings = require "RelentlessDead/Settings"

-- What other mods gave through the API: drivers, vetoes and before-rise functions, each under a
-- name, in the order the names were first given. Rising, on the server and in single player, uses
-- them, and sets keepDown and report here for the API.
local Hooks = {}

local drivers, vetoes, befores = {}, {}, {}

-- Replaces the value under name, adds it at the end, or removes it when value is nil.
local function put(list, name, value)
    for i, entry in ipairs(list) do
        if entry.name == name then
            if value == nil then
                table.remove(list, i)
            else
                entry.value = value
            end
            return
        end
    end
    if value ~= nil then
        list[#list + 1] = { name = name, value = value }
    end
end

local function names(list)
    local out = {}
    for _, entry in ipairs(list) do
        out[#out + 1] = entry.name
    end
    return out
end

-- Why phase isn't { rise = 0 to 100, wake = true or false, label = text or nil }, or nil.
function Hooks.invalid(phase)
    if type(phase) ~= "table" then
        return "the phase is not a table"
    end
    local rise = phase.rise
    if type(rise) ~= "number" or rise ~= rise or rise < 0 or rise > 100 then
        return "rise is not a number from 0 to 100"
    end
    if type(phase.wake) ~= "boolean" then
        return "wake is not true or false"
    end
    if phase.label ~= nil and type(phase.label) ~= "string" then
        return "label is not a text"
    end
    return nil
end

function Hooks.drive(name, phase)
    put(drivers, name, phase)
    if #drivers > 1 then
        Log.warnOnce("drivers", table.concat(names(drivers), " and ") .. " all drive rising; the first that gives a phase decides")
    end
end

function Hooks.veto(name, fn)
    put(vetoes, name, fn)
end

function Hooks.before(name, fn)
    put(befores, name, fn)
end

-- The phase the driver gives now, or nil.
local function given(entry)
    local phase = entry.value
    if type(phase) == "function" then
        local ok, result = pcall(phase)
        if not ok then
            Log.warnOnce("driver failed " .. entry.name, "the driver " .. entry.name .. " failed (" .. tostring(result)
                .. "), so it drives nothing")
            return nil
        end
        phase = result
        if phase ~= nil then
            local why = Hooks.invalid(phase)
            if why ~= nil then
                Log.warnOnce("driver invalid " .. entry.name, "the driver " .. entry.name .. " gave a phase where " .. why
                    .. ", so it drives nothing")
                return nil
            end
        end
    end
    return phase
end

-- { rise, wake, label, driver }: the first driver's phase, else the mod's own options, with which a
-- due corpse always gets up.
function Hooks.phase()
    for _, entry in ipairs(drivers) do
        local phase = given(entry)
        if phase ~= nil then
            return { rise = phase.rise, wake = phase.wake, label = phase.label, driver = entry.name }
        end
    end
    return { rise = Settings.riseChance(), wake = true }
end

-- "name: reason" of the first veto that keeps z down, or nil. A veto that fails keeps nothing down.
function Hooks.vetoed(z)
    for _, entry in ipairs(vetoes) do
        local ok, reason = pcall(entry.value, z)
        if not ok then
            Log.warnOnce("veto failed " .. entry.name, "the veto " .. entry.name .. " failed (" .. tostring(reason)
                .. "), so it keeps nothing down")
        elseif type(reason) == "string" then
            return entry.name .. ": " .. reason
        elseif reason then
            return entry.name
        end
    end
    return nil
end

-- Runs the before-rise functions on the corpse; one that fails doesn't stop the rise.
function Hooks.beforeRise(body)
    for _, entry in ipairs(befores) do
        local ok, err = pcall(entry.value, body)
        if not ok then
            Log.warnOnce("before rise failed " .. entry.name, "the before-rise function " .. entry.name .. " failed ("
                .. tostring(err) .. ")")
        end
    end
end

function Hooks.status()
    local function list(t)
        if #t == 0 then
            return "none"
        end
        return table.concat(t, ", ")
    end
    return "other mods: drivers " .. list(names(drivers)) .. "; vetoes " .. list(names(vetoes)) .. "; before rise "
        .. list(names(befores))
end

return Hooks
