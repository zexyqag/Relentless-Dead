local Body = require "RelentlessDead/Body"
local Hooks = require "RelentlessDead/Hooks"

-- The admin's Status: a line over the head, and the details in the log.

local function allowed(player)
    if not isClient() or getDebug() then
        return true
    end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions)
end

local function show(reply)
    local player = getSpecificPlayer(reply.player)
    if player == nil then
        return
    end
    for _, line in ipairs(reply.lines or {}) do
        print("[RelentlessDead] " .. line)
    end
    local args = {}
    for i, arg in ipairs(reply.args or {}) do
        if type(arg) == "table" then
            args[i] = getText(arg.key)
        else
            args[i] = arg
        end
    end
    player:setHaloNote(getText(reply.text, unpack(args)), 255, 255, 255, 300)
end

local function status(playerIndex)
    if isClient() then
        sendClientCommand(getSpecificPlayer(playerIndex), Body.MODULE, "status", { player = playerIndex })
    else
        local reply = Hooks.report()
        reply.player = playerIndex
        show(reply)
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if player ~= nil and allowed(player) then
        context:addOption(getText("ContextMenu_RelentlessDead_Status"), playerIndex, status)
    end
end)

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == Body.MODULE and command == "status" then
            show(args)
        end
    end)
end
