-- ==========================================================================
-- render/TimerText.lua
-- ==========================================================================
-- Purpose:  Shared numeric timer text for aura and cooldown icon overlays.
--           Renders integer-second countdowns on icon overlay frames.
-- Owns:     A hidden updater frame and registry of visible timed overlay frames.
-- Does NOT: Create icon frames, know about sweeps, or interact with the
--           dirty-GUID pipeline.
-- Used by:  IconFill (strip icons), TargetPortraitRenderer (portrait badge).
-- Calls:    FontString:SetText (cached; only when displayed value changes).
-- ==========================================================================

local TimerText = AzF.TimerText

local GetTime = GetTime
local ceil    = math.ceil
local floor   = math.floor
local format  = string.format

-- The updater frame, created by Init. Hidden when no frames are active.
local updater = nil

-- Throttle accumulator for the updater's OnUpdate.
local tickElapsed  = 0
local TICK_INTERVAL = 0.1

-- Multi-frame registry. Array + index map for O(1) dedup and swap-remove.
local activeFrames = {}  -- [i] = overlay frame
local frameIndex   = {}  -- [frame] = i
local activeCount  = 0

-- Swap-remove a frame from the registry by its index.
local function Deregister(frame, idx)
    local last = activeFrames[activeCount]
    if last ~= frame then
        activeFrames[idx] = last
        frameIndex[last]  = idx
    end
    activeFrames[activeCount] = nil
    frameIndex[frame]         = nil
    activeCount = activeCount - 1
end

-- Lazily create (or reuse) a FontString on an overlay frame.
-- Font size is derived from the frame's height so it scales for both
-- 24px target icons and 16px nameplate icons without caller coordination.
local function EnsureFontString(frame)
    if frame.azfTimerFS then return frame.azfTimerFS end

    local h    = frame:GetHeight() or 16
    local size = h * 0.55
    if size < 8  then size = 8  end
    if size > 16 then size = 16 end

    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(0.9, 0.9, 0.2, 1)
    fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.azfTimerFS = fs
    return fs
end

-- Format remaining seconds into display text.
-- >3s: whole seconds (floor). <=3s: one decimal. >=60s: minutes.
-- Returns nil when remaining <= 0 (caller should hide text).
local function FormatRemaining(remaining)
    if remaining <= 0 then return nil end
    if remaining >= 60 then
        return ceil(remaining / 60) .. "m"
    end
    if remaining <= 3 then
        return format("%.1f", remaining)
    end
    return tostring(floor(remaining))
end

-- Write text to a frame, skipping the SetText API call when cached value matches.
local function ApplyText(frame, remaining)
    local text = FormatRemaining(remaining)
    if text then
        local fs = EnsureFontString(frame)
        if text ~= frame.azfTimerVal then
            fs:SetText(text)
            frame.azfTimerVal = text
        end
        fs:Show()
    else
        local fs = frame.azfTimerFS
        if fs then fs:Hide() end
        frame.azfTimerVal = nil
    end
end

function TimerText:Init()
    if updater then return end

    updater = CreateFrame("Frame", nil, UIParent)
    updater:Hide()

    updater:SetScript("OnUpdate", function()
        tickElapsed = tickElapsed + arg1
        if tickElapsed < TICK_INTERVAL then return end
        tickElapsed = 0

        local now = GetTime()
        local i = 1
        while i <= activeCount do
            local f         = activeFrames[i]
            local remaining = f.azfTimerExpires - now

            if remaining <= 0 then
                -- Expired: hide text and deregister.
                local fs = f.azfTimerFS
                if fs then fs:Hide() end
                f.azfTimerVal = nil
                Deregister(f, i)
                -- do not increment i; the swapped-in element needs re-checking
            else
                ApplyText(f, remaining)
                i = i + 1
            end
        end

        if activeCount == 0 then
            updater:Hide()
        end
    end)
end

-- Register an overlay frame for timer display.
-- Paints text immediately so there is no visible pop on the first tick.
-- Safe to call on an already-registered frame (updates expiresAt in place).
function TimerText:Start(frame, expiresAt)
    if not frame or not expiresAt then
        self:Stop(frame)
        return
    end

    frame.azfTimerExpires = expiresAt

    -- Paint immediately, mirroring how ReverseSweep:Start sets sequence time
    -- before returning so the first rendered frame is already correct.
    ApplyText(frame, expiresAt - GetTime())

    -- Deduplicate: if already registered, fields are updated above.
    if frameIndex[frame] then
        updater:Show()
        return
    end

    activeCount = activeCount + 1
    activeFrames[activeCount] = frame
    frameIndex[frame]         = activeCount

    updater:Show()
end

-- Deregister an overlay frame and hide its timer text.
-- Safe to call on a frame that is not registered (no-op).
function TimerText:Stop(frame)
    if not frame then return end

    local idx = frameIndex[frame]
    if not idx then return end

    local fs = frame.azfTimerFS
    if fs then fs:Hide() end
    frame.azfTimerVal = nil

    Deregister(frame, idx)

    if activeCount == 0 then
        updater:Hide()
    end
end

-- Stop all registered frames. Used on zone change.
function TimerText:StopAll()
    for i = 1, activeCount do
        local f  = activeFrames[i]
        local fs = f.azfTimerFS
        if fs then fs:Hide() end
        f.azfTimerVal = nil
        activeFrames[i] = nil
        frameIndex[f]   = nil
    end
    activeCount = 0
    if updater then updater:Hide() end
end
