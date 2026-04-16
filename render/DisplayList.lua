-- ==========================================================================
-- render/DisplayList.lua
-- ==========================================================================
-- Purpose:  Shared display selection for aura and cooldown strips.
--           Produces deterministic, priority-sorted arrays from raw SpellState
--           for renderers to consume. Owns the canonical display ordering policy.
-- Owns:     SelectAuras, SelectCooldowns, the sort comparator, buffer management.
-- Does NOT: Create frames, subscribe to events, or know about slot counts.
-- Used by:  VisualSync calls Select* once per dirty GUID, passes results to
--           TargetRenderer, NameplateRenderer, TargetPortraitRenderer.
-- Calls:    AzF.SpellDB (icon/priority/dispelType lookup).
-- ==========================================================================

local DisplayList = AzF.DisplayList
local SpellDB     = AzF.SpellDB

local DEFAULT_PRIORITY = 99

-- Module-level reusable sort buffers. Safe because Lua is single-threaded
-- and only one GUID flushes at a time. Slot tables are created lazily and
-- fields are overwritten in place (zero allocations in steady state).
local auraBuf   = {}
local cdBuf     = {}

-- Display sort order (total, deterministic):
-- 1. priority ascending (lower = more important)
-- 2. Timed entry before permanent (has expiresAt wins)
-- 3. Shorter remaining duration first (lower expiresAt)
-- 4. Earlier startedAt first (older application wins ties)
-- 5. Lower spellId (stable fallback, prevents flicker)
local function SortByPriority(a, b)
    if a.priority ~= b.priority then
        return a.priority < b.priority
    end

    local aExp = a.expiresAt
    local bExp = b.expiresAt

    -- Timed entry beats permanent.
    if aExp and not bExp then return true end
    if bExp and not aExp then return false end

    -- Both timed: shorter remaining duration wins.
    if aExp and bExp and aExp ~= bExp then
        return aExp < bExp
    end

    -- Earlier application wins.
    local aStart = a.startedAt
    local bStart = b.startedAt
    if aStart and bStart and aStart ~= bStart then
        return aStart < bStart
    end

    -- Stable fallback.
    return a.spellId < b.spellId
end

-- Select and sort active auras for display.
-- Returns the shared auraBuf array and the number of valid entries.
function DisplayList:SelectAuras(state, now)
    local count = 0

    if state and state.auras then
        for spellId, entry in pairs(state.auras) do
            if not entry.expiresAt or entry.expiresAt > now then
                local spellData = SpellDB[spellId]
                if spellData and spellData.iconTexture then
                    count = count + 1
                    local slot = auraBuf[count]
                    if not slot then
                        slot = {}
                        auraBuf[count] = slot
                    end
                    slot.spellId     = spellId
                    slot.priority    = spellData.classPriority or spellData.priority or DEFAULT_PRIORITY
                    slot.iconTexture = spellData.iconTexture
                    slot.startedAt   = entry.startedAt
                    slot.expiresAt   = entry.expiresAt
                    slot.dispelType  = spellData.dispelType
                end
            end
        end
    end

    -- Nil stale trailing entries so table.getn / table.sort see correct length.
    local prevLen = table.getn(auraBuf)
    for i = count + 1, prevLen do
        auraBuf[i] = nil
    end

    if count > 1 then
        table.sort(auraBuf, SortByPriority)
    end

    return auraBuf, count
end

-- Select and sort active cooldowns for display.
-- Returns the shared cdBuf array and the number of valid entries.
function DisplayList:SelectCooldowns(state, now)
    local count = 0

    if state and state.cooldowns then
        for spellId, entry in pairs(state.cooldowns) do
            if entry.expiresAt and entry.expiresAt > now then
                local spellData = SpellDB[spellId]
                if spellData and spellData.iconTexture then
                    count = count + 1
                    local slot = cdBuf[count]
                    if not slot then
                        slot = {}
                        cdBuf[count] = slot
                    end
                    slot.spellId     = spellId
                    slot.priority    = spellData.classPriority or spellData.priority or DEFAULT_PRIORITY
                    slot.iconTexture = spellData.iconTexture
                    slot.startedAt   = entry.startedAt
                    slot.expiresAt   = entry.expiresAt
                end
            end
        end
    end

    local prevLen = table.getn(cdBuf)
    for i = count + 1, prevLen do
        cdBuf[i] = nil
    end

    if count > 1 then
        table.sort(cdBuf, SortByPriority)
    end

    return cdBuf, count
end
