-- ==========================================================================
-- core/Slash.lua
-- ==========================================================================
-- Purpose:  Owns the /azf slash command and dispatches subcommands to
--           registered handlers.
-- Owns:     Slash registration, subcommand registry, and argument splitting.
-- Does NOT: Implement feature-specific slash behavior.
-- ==========================================================================

local Slash = AzF.Slash

local initialized = false
local handlers = {}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[AbstractzFrames]|r " .. message)
end

local function SplitFirstToken(message)
    local trimmed = string.gsub(message or "", "^%s+", "")
    if trimmed == "" then
        return nil, ""
    end

    local _, firstSpace = string.find(trimmed, "%s")
    if not firstSpace then
        return string.lower(trimmed), ""
    end

    local command = string.lower(string.sub(trimmed, 1, firstSpace - 1))
    local rest = string.gsub(string.sub(trimmed, firstSpace + 1), "^%s+", "")
    return command, rest
end

function Slash:Register(command, handler)
    if not command or command == "" then return end
    if type(handler) ~= "function" then return end
    handlers[string.lower(command)] = handler
end

function Slash:Handle(message)
    local command, rest = SplitFirstToken(message)
    if not command then
        Print("Use '/azf mock ...'.")
        return
    end

    local handler = handlers[command]
    if not handler then
        Print("Unknown command '" .. command .. "'.")
        return
    end

    handler(rest)
end

function Slash:Init()
    if initialized then return end
    initialized = true

    SLASH_AZF1 = "/azf"
    SlashCmdList["AZF"] = function(message)
        Slash:Handle(message)
    end
end
