-- ==========================================================================
-- core/Player.lua
-- ==========================================================================
-- Purpose:  Captures and exposes local-player identity for runtime logic.
-- Owns:     Session-local player class and GUID values.
-- Does NOT: Register events, mutate feature state, or own startup ordering.
-- Used by:  AbstractzFrames.lua and future logic that needs player identity.
-- ==========================================================================

local Player = AzF.Player

local playerClass = nil
local playerGuid = nil

function Player:Init()
    playerClass = string.upper(UnitClass("player"))
    playerGuid = GetUnitGUID("player")

    return playerClass, playerGuid
end

function Player:GetClass()
    return playerClass
end

function Player:GetGuid()
    return playerGuid
end
