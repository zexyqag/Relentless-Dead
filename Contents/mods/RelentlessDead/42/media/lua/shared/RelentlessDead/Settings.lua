local Log = require "RelentlessDead/Log"

local Settings = {}

local DEFAULTS = {
    RiseChance = 50,
    RiseDelayMin = 1.0,
    RiseDelayMax = 2.0,
    MaxRises = 0,
    RiseMaxAgeHours = 168,
    RiseWarning = true,
    RiseWarningMinutes = 2,
    FireStaysDown = true,
    FinishOff = true,
    FinishOffSeconds = 3,
    HeadKillsStayDown = false,
    RiseInSafehouses = false,
    RisePlayers = false,
    RisesPerScan = 10,
    RiserLimit = 5000,
}

local function invalid(name, value)
    Log.warnOnce("setting " .. name, "RelentlessDead." .. name .. " is " .. tostring(value)
        .. ", which is not a valid value; using " .. tostring(DEFAULTS[name]))
    return DEFAULTS[name]
end

local function read(name)
    local vars = SandboxVars.RelentlessDead
    if vars == nil then
        return nil
    end
    return vars[name]
end

local function integer(name, min, max)
    local value = read(name)
    if type(value) ~= "number" or value ~= math.floor(value) or value < min or value > max then
        return invalid(name, value)
    end
    return value
end

local function number(name, min, max)
    local value = read(name)
    if type(value) ~= "number" or value < min or value > max then
        return invalid(name, value)
    end
    return value
end

local function boolean(name)
    local value = read(name)
    if type(value) ~= "boolean" then
        return invalid(name, value)
    end
    return value
end

-- Percent of the killed zombies marked to rise while no other mod drives rising.
function Settings.riseChance()
    return integer("RiseChance", 0, 100)
end

-- In-game hours after death before a marked corpse may get up.
function Settings.riseDelayMin()
    return number("RiseDelayMin", 0, 48)
end

function Settings.riseDelayMax()
    return number("RiseDelayMax", 0, 48)
end

-- The two, the lower first.
function Settings.riseDelay()
    local low, high = Settings.riseDelayMin(), Settings.riseDelayMax()
    if low > high then
        Log.warnOnce("setting RiseDelay", "RelentlessDead.RiseDelayMin is " .. tostring(low) .. ", above RelentlessDead.RiseDelayMax "
            .. tostring(high) .. "; using " .. tostring(high) .. " to " .. tostring(low))
        return high, low
    end
    return low, high
end

-- 0 for no limit.
function Settings.maxRises()
    return integer("MaxRises", 0, 20)
end

-- 0 for no limit.
function Settings.riseMaxAgeHours()
    return integer("RiseMaxAgeHours", 0, 8760)
end

function Settings.riseWarning()
    return boolean("RiseWarning")
end

-- In-game minutes from a corpse's groan until it gets up.
function Settings.riseWarningMinutes()
    return integer("RiseWarningMinutes", 1, 10)
end

function Settings.fireStaysDown()
    return boolean("FireStaysDown")
end

function Settings.finishOff()
    return boolean("FinishOff")
end

function Settings.finishOffSeconds()
    return integer("FinishOffSeconds", 1, 30)
end

function Settings.headKillsStayDown()
    return boolean("HeadKillsStayDown")
end

function Settings.riseInSafehouses()
    return boolean("RiseInSafehouses")
end

function Settings.risePlayers()
    return boolean("RisePlayers")
end

function Settings.risesPerScan()
    return integer("RisesPerScan", 1, 100)
end

function Settings.riserLimit()
    return integer("RiserLimit", 100, 50000)
end

return Settings
