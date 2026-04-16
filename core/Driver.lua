-- ==========================================================================
-- core/Driver.lua
-- ==========================================================================
-- Purpose:  Hidden frame with a single OnUpdate that runs the addon's
--           periodic work: process expired entries and flush dirty GUIDs
--           to the visual layer.
-- Owns:     The driver frame, the throttle accumulator, and the flush loop.
-- Does NOT: Own spell state, active frames, expiry data, or rendering logic.
-- Used by:  Runs automatically via OnUpdate. No external callers.
-- Calls:    AzF.ExpiryIndex (ProcessExpiries), AzF.Casts (ProcessExpiries),
--           AzF.SpellState (GetStateTable, GetDirtyGuids, MarkDirty),
--           AzF.VisualSync (UpdateGuid).
-- ==========================================================================

local Driver      = AzF.Driver
local ExpiryIndex = AzF.ExpiryIndex
local Casts       = AzF.Casts
local SpellState  = AzF.SpellState
local VisualSync  = AzF.VisualSync

local DRIVER_INTERVAL = 0.05
local elapsed = 0

-- Wrapper to pass MarkDirty as a plain function reference with self bound.
local function markDirty(guid)
    SpellState:MarkDirty(guid)
end

-- Flush all dirty GUIDs to the visual layer.
local function FlushDirtyGuids()
    local dirtyGuids = SpellState:GetDirtyGuids()
    -- Iterating with pairs() while setting keys to nil is safe in Lua 5.1.
    for guid in pairs(dirtyGuids) do
        dirtyGuids[guid] = nil
        VisualSync:UpdateGuid(guid)
    end
end

-- The hidden driver frame. No name, parent, or size needed — purely a scheduler.
local driverFrame = CreateFrame("Frame")

driverFrame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < DRIVER_INTERVAL then return end
    elapsed = 0

    local now = GetTime()
    ExpiryIndex:ProcessExpiries(now, SpellState:GetStateTable(), markDirty)
    Casts:ProcessExpiries(now)
    FlushDirtyGuids()
end)

-- Init provided for consistency with other modules. No setup needed beyond
-- the frame creation above, which happens at file scope.
function Driver:Init()
end
