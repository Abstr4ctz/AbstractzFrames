-- ==========================================================================
-- render/ReverseSweep.lua
-- ==========================================================================
-- Purpose:  Drives reverse cooldown sweep animation (empty-to-filled) for
--           aura models. The dark region starts empty and grows clockwise
--           as the aura duration expires.
-- Owns:     A hidden updater frame and multi-model Start/Stop registration.
-- Does NOT: Create models, decide which aura wins, or know about SpellDB.
-- Used by:  TargetPortraitRenderer (direct), IconFill (strip renderers).
-- Calls:    Model:SetSequenceTime (cached per model).
-- ==========================================================================

local ReverseSweep = AzF.ReverseSweep

local GetTime = GetTime

-- The updater frame, created by Init. Hidden when no models are active.
local updater = nil

-- Multi-model registry. Array + index map for O(1) dedup and swap-remove.
local activeModels = {}   -- [i] = model
local modelIndex   = {}   -- [model] = i
local activeCount  = 0

-- Swap-remove a model from the registry by its index.
local function Deregister(model, idx)
    local last = activeModels[activeCount]
    if last ~= model then
        activeModels[idx] = last
        modelIndex[last] = idx
    end
    activeModels[activeCount] = nil
    modelIndex[model] = nil
    activeCount = activeCount - 1
end

function ReverseSweep:Init()
    if updater then return end

    updater = CreateFrame("Frame", nil, UIParent)
    updater:Hide()

    updater:SetScript("OnUpdate", function()
        if activeCount == 0 then
            updater:Hide()
            return
        end

        local time = GetTime()
        local i = 1
        while i <= activeCount do
            local m = activeModels[i]
            local progress = (time - m.azfSweepStart) / m.azfSweepDuration

            if progress < 1.0 then
                m.azfSetSequenceTime(m, 0, 1000 - (progress * 1000))
                i = i + 1
            else
                m.azfSetSequenceTime(m, 0, 0)
                m:Hide()
                Deregister(m, i)
                -- do not increment i; re-check the swapped-in element
            end
        end

        if activeCount == 0 then
            updater:Hide()
        end
    end)
end

function ReverseSweep:Start(model, startTime, duration)
    if not model or not startTime or not duration or duration <= 0 then
        self:Stop(model)
        return
    end

    model.azfSweepStart    = startTime
    model.azfSweepDuration = duration
    model.azfSetSequenceTime = model.azfSetSequenceTime or model.SetSequenceTime

    -- Set initial sequence immediately so the first rendered frame is correct.
    local now = GetTime()
    local progress = (now - startTime) / duration
    if progress < 0 then progress = 0 end
    if progress >= 1.0 then
        model.azfSetSequenceTime(model, 0, 0)
        model:Hide()
        local idx = modelIndex[model]
        if idx then
            Deregister(model, idx)
            if activeCount == 0 then updater:Hide() end
        end
        return
    end
    model.azfSetSequenceTime(model, 0, 1000 - (progress * 1000))

    -- Deduplicate: if already registered, fields are updated above, nothing else to do.
    if modelIndex[model] then
        model:Show()
        updater:Show()
        return
    end

    activeCount = activeCount + 1
    activeModels[activeCount] = model
    modelIndex[model] = activeCount

    model:Show()
    updater:Show()
end

function ReverseSweep:Stop(model)
    if not model then return end

    local idx = modelIndex[model]
    if not idx then return end

    model.azfSetSequenceTime = model.azfSetSequenceTime or model.SetSequenceTime
    model.azfSetSequenceTime(model, 0, 0)
    model:Hide()
    Deregister(model, idx)

    if activeCount == 0 then
        updater:Hide()
    end
end
