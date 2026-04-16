-- ==========================================================================
-- render/VisualSync.lua
-- ==========================================================================
-- Purpose:  Takes a GUID that needs a visual refresh, checks which UI
--           destinations are active for it, and dispatches the update to
--           each destination.
-- Owns:     The UpdateGuid dispatch function.
-- Does NOT: Own frames, spell state, active frames, or timing logic.
-- Used by:  Driver calls UpdateGuid for each dirty GUID.
-- Calls:    AzF.ActiveFrames (GetEntry), AzF.SpellState (GetExisting),
--           AzF.TargetRenderer (Refresh, Hide).
-- ==========================================================================

local VisualSync      = AzF.VisualSync
local ActiveFrames    = AzF.ActiveFrames
local SpellState      = AzF.SpellState
local DisplayList             = AzF.DisplayList
local TargetRenderer          = AzF.TargetRenderer
local TargetPortraitRenderer  = AzF.TargetPortraitRenderer
local NameplateRenderer       = AzF.NameplateRenderer

-- Route a GUID update to all active UI destinations.
function VisualSync:UpdateGuid(guid)
    local frames = ActiveFrames:GetEntry(guid)
    if not frames or frames.count == 0 then return end

    local state = SpellState:GetExisting(guid)
    local now = GetTime()

    local auraBuf, auraCount = DisplayList:SelectAuras(state, now)
    local cdBuf, cdCount     = DisplayList:SelectCooldowns(state, now)

    if frames.target then
        TargetRenderer:Refresh(auraBuf, auraCount, cdBuf, cdCount)
        TargetPortraitRenderer:Refresh(auraBuf, auraCount)
    end

    if frames.nameplate then
        NameplateRenderer:Refresh(frames.nameplate, state, auraBuf, auraCount, cdBuf, cdCount)
    end

    -- Future slots:
    -- if frames.arena then ArenaRenderer:Refresh(...) end
    -- if frames.focus then FocusRenderer:Refresh(...) end
end

-- Immediate target-change notification from the binding layer.
-- Shows current state or hides the renderer when the target is cleared.
function VisualSync:OnTargetChanged(newGuid)
    if newGuid then
        local state = SpellState:GetExisting(newGuid)
        local now = GetTime()
        local auraBuf, auraCount = DisplayList:SelectAuras(state, now)
        local cdBuf, cdCount     = DisplayList:SelectCooldowns(state, now)
        TargetRenderer:Refresh(auraBuf, auraCount, cdBuf, cdCount)
        TargetPortraitRenderer:Refresh(auraBuf, auraCount)
    else
        TargetRenderer:Hide()
        TargetPortraitRenderer:Hide()
    end
end

-- Immediate nameplate-show notification from the binding layer.
function VisualSync:OnNameplateShow(guid, plate)
    local state = SpellState:GetExisting(guid)
    local now = GetTime()
    local auraBuf, auraCount = DisplayList:SelectAuras(state, now)
    local cdBuf, cdCount     = DisplayList:SelectCooldowns(state, now)
    NameplateRenderer:Refresh(plate, state, auraBuf, auraCount, cdBuf, cdCount)
end

-- Immediate nameplate-hide notification from the binding layer.
function VisualSync:OnNameplateHide(plate)
    NameplateRenderer:HideOverlay(plate)
end
