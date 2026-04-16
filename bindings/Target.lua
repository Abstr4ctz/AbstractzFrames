-- ==========================================================================
-- bindings/Target.lua
-- ==========================================================================
-- Purpose:  Keeps ActiveFrames updated when the player's target changes.
-- Owns:     The PLAYER_TARGET_CHANGED subscription and the cached current
--           target GUID.
-- Does NOT: Render anything, own spell state, or know about specific spells.
-- Used by:  EventBus dispatches PLAYER_TARGET_CHANGED to this module.
-- Calls:    AzF.ActiveFrames (SetSlot, ClearSlot),
--           AzF.VisualSync (OnTargetChanged), AzF.EventBus (Subscribe).
--           WoW API: UnitExists, GetUnitGUID.
-- ==========================================================================

local Target       = AzF.Target
local ActiveFrames = AzF.ActiveFrames
local EventBus     = AzF.EventBus
local VisualSync   = AzF.VisualSync

-- Cached GUID of the player's current target.
local currentTargetGuid = nil

-- Return the current target GUID if the player has a valid target.
local function GetCurrentTargetGuid()
    if not UnitExists("target") then
        return nil
    end

    local guid = GetUnitGUID("target")
    if not guid or guid == "" then
        return nil
    end

    return guid
end

-- Handle target change: clear old slot, set new slot, mark dirty.
local function onTargetChanged()
    if currentTargetGuid then
        ActiveFrames:ClearSlot(currentTargetGuid, "target")
    end

    local newTargetGuid = GetCurrentTargetGuid()
    if newTargetGuid then
        ActiveFrames:SetSlot(newTargetGuid, "target", true)
    end

    currentTargetGuid = newTargetGuid

    -- Notify visual layer immediately: show target data or hide frame.
    VisualSync:OnTargetChanged(newTargetGuid)
end

-- Subscribe to PLAYER_TARGET_CHANGED and capture current target if one exists.
function Target:Init()
    EventBus:Subscribe("PLAYER_TARGET_CHANGED", onTargetChanged)
    onTargetChanged()
end
