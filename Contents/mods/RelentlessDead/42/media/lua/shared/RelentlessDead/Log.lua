local Log = {}

local PREFIX = "[RelentlessDead] "
local warned = {}

-- Reads its own setting so that Settings can log through this module.
local function verbose()
    local vars = SandboxVars.RelentlessDead
    return vars ~= nil and vars.Verbose == true
end

function Log.info(message)
    if verbose() then
        print(PREFIX .. message)
    end
end

function Log.warn(message)
    print(PREFIX .. "WARNING: " .. message)
end

function Log.error(message)
    print(PREFIX .. "ERROR: " .. message)
end

function Log.warnOnce(key, message)
    if warned[key] then
        return
    end
    warned[key] = true
    Log.warn(message)
end

return Log
