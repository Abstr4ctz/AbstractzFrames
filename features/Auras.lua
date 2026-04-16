-- ==========================================================================
-- features/Auras.lua
-- ==========================================================================
-- Purpose:  Tracks aura (buff/debuff) application and removal for spells
--           with trackAura = true. Handles miss filtering, duplicate-effect
--           guarding, DR integration, removal, death cleanup, and DR drift
--           correction via DEBUFF_ADDED_OTHER.
-- Owns:     Route registrations for aura-tracked spells, miss tracking,
--           aura write/remove logic, and max-stack DR correction.
-- Does NOT: Parse raw event args (Router does that), render frames, or
--           manage expiry cleanup.
-- Used by:  Router dispatches AURA_CAST_ON_OTHER, SPELL_MISS_OTHER,
--           BUFF_REMOVED_OTHER, DEBUFF_REMOVED_OTHER, DEBUFF_ADDED_OTHER,
--           UNIT_DIED. _SELF variants are routed transparently through the
--           _OTHER dispatchers via SELF_SIBLINGS in Router.
-- Calls:    AzF.SpellDB (lookup), AzF.SpellState (GetEntry, GetExisting,
--           MarkDirty, ClearAurasAndDR), AzF.DR (Apply), AzF.Router (AddRoute).
-- targetMode semantics used here:
--   "self"  — aura always lands on caster; nil targetGuid falls back to casterGuid.
--   "other" — aura never lands on caster; events where targetGuid==casterGuid are
--             spurious nampower artifacts (miss path) and are rejected.
--   "both"  — aura may land on anyone; no fallback, no filter.
-- ==========================================================================

local SpellDB     = AzF.SpellDB
local SpellState  = AzF.SpellState
local Router      = AzF.Router
local DR          = AzF.DR
local ExpiryIndex = AzF.ExpiryIndex
local Auras       = AzF.Auras

-- Time window in seconds for grouping events from a single cast batch.
-- Governs both miss expiry and duplicate-effect detection.
local CAST_BATCH_WINDOW = 0.05

-- =========================================================================
-- Miss tracking
-- =========================================================================
-- Parallel flat arrays of recent miss events. Entries expire by time, never
-- consumed on match, so multi-effect spells are fully suppressed.
-- Using parallel arrays instead of an array-of-tables to avoid per-miss
-- table allocation (misses are ultra-short-lived, ~50ms).
-- =========================================================================

local missCasterGuids = {}
local missSpellIds    = {}
local missTargetGuids = {}
local missTimes       = {}
local missCount       = 0

-- Record a miss so subsequent AURA_CAST events for this target are suppressed.
-- Only targetGuid is required. Nil casterGuid is allowed so stealth misses
-- are recorded. wasMissed matches nil==nil for casterGuid, which correctly
-- suppresses the aura. Two invisible casters with the same spell+target in
-- one batch window would cross-match — accepted as practically impossible.
local function onSpellMiss(eventName, casterGuid, targetGuid, spellId, missInfo)
    if not targetGuid then return end

    missCount = missCount + 1
    missCasterGuids[missCount] = casterGuid
    missSpellIds[missCount]    = spellId
    missTargetGuids[missCount] = targetGuid
    missTimes[missCount]       = GetTime()
end

-- Check whether a recent miss exists for this caster+spell+target combo.
-- Expired entries are pruned via swap-remove. Matching entries are NOT consumed.
local function wasMissed(casterGuid, spellId, targetGuid, now)
    local i = missCount
    while i >= 1 do
        if (now - missTimes[i]) > CAST_BATCH_WINDOW then
            -- Expired: swap-remove. Do not decrement i — the element swapped
            -- in from the tail must be re-examined in the next iteration.
            missCasterGuids[i] = missCasterGuids[missCount]
            missSpellIds[i]    = missSpellIds[missCount]
            missTargetGuids[i] = missTargetGuids[missCount]
            missTimes[i]       = missTimes[missCount]
            missCasterGuids[missCount] = nil
            missSpellIds[missCount]    = nil
            missTargetGuids[missCount] = nil
            missTimes[missCount]       = nil
            missCount = missCount - 1
            -- If we just removed the tail element, step back to the new tail.
            if i > missCount then
                i = missCount
            end
        elseif missCasterGuids[i] == casterGuid
           and missSpellIds[i] == spellId
           and missTargetGuids[i] == targetGuid then
            return true
        else
            i = i - 1
        end
    end
    return false
end

-- Return true if this spell+caster was already written within the batch window.
-- Multi-effect spells (e.g. Kidney Shot) fire multiple AURA_CAST events per
-- target per cast. Only the first should be processed.
local function isDuplicateAura(entry, spellId, casterGuid, now)
    local auraEntry = entry.auras[spellId]
    if not auraEntry then return false end
    return auraEntry.casterGuid == casterGuid
       and (now - auraEntry.writeTime) <= CAST_BATCH_WINDOW
end

-- =========================================================================
-- DR drift correction — max-stack tracking
-- =========================================================================
-- When our DR tracker says "immune" (stacks >= 4) but the server actually
-- applies the debuff, we silently suppress a real CC. This is the addon's
-- worst failure mode. To fix it, we track GUIDs at max DR stacks and
-- subscribe to DEBUFF_ADDED_OTHER to detect when the server disagrees.
-- =========================================================================

-- Tracks GUIDs that reached max DR stacks (immune). Keyed by drCat, then guid.
-- maxStackGuids["stun"]["0xABC123"] = true means that GUID is at max stun DR.
local maxStackGuids = {}

-- Total number of GUID+drCat entries in maxStackGuids.
-- When this goes from 0 to 1, subscribe DEBUFF_ADDED_OTHER.
-- When it goes to 0, unsubscribe.
local maxStackTotal = 0

-- Forward declaration. Defined after writeAura.
local onDebuffAdded

-- Record that a GUID reached max DR stacks for a category.
-- Subscribes to DEBUFF_ADDED_OTHER when the first max-stack GUID is added.
local function addMaxStack(guid, drCat)
    local catSet = maxStackGuids[drCat]
    if not catSet then
        catSet = {}
        maxStackGuids[drCat] = catSet
    end
    if catSet[guid] then return end -- already tracked

    catSet[guid] = true
    maxStackTotal = maxStackTotal + 1

    if maxStackTotal == 1 then
        Router:AddRoute("DEBUFF_ADDED_OTHER", "ANY", onDebuffAdded)
    end
end

-- Remove a GUID from max-stack tracking for one or all categories.
-- Unsubscribes from DEBUFF_ADDED_OTHER when no max-stack GUIDs remain.
local function removeMaxStack(guid, drCat)
    if drCat then
        -- Remove one specific category.
        local catSet = maxStackGuids[drCat]
        if not catSet or not catSet[guid] then return end
        catSet[guid] = nil
        if not next(catSet) then
            maxStackGuids[drCat] = nil
        end
        maxStackTotal = maxStackTotal - 1
    else
        -- Remove all categories for this GUID (used on death).
        for cat, catSet in pairs(maxStackGuids) do
            if catSet[guid] then
                catSet[guid] = nil
                maxStackTotal = maxStackTotal - 1
                if not next(catSet) then
                    maxStackGuids[cat] = nil
                end
            end
        end
    end

    if maxStackTotal == 0 then
        Router:RemoveRoute("DEBUFF_ADDED_OTHER", "ANY", onDebuffAdded)
    end
end

-- =========================================================================
-- Aura write helper
-- =========================================================================
-- Write an aura entry to SpellState. Handles unscheduling old expiry,
-- writing the new entry, scheduling new expiry, and marking dirty.
-- Used by both normal aura application and DR drift correction.

local function writeAura(targetGuid, spellId, casterGuid, dimDuration, drStacks, now)
    local entry = SpellState:GetEntry(targetGuid)

    -- Unschedule old aura expiry if overwriting.
    local oldAura = entry.auras[spellId]
    if oldAura then
        ExpiryIndex:Unschedule(oldAura, targetGuid)
    end

    -- Write aura entry. Reuse the old table if available — it was just
    -- unscheduled above, so no external references remain.
    local auraEntry = oldAura or {}
    auraEntry.startedAt  = now
    auraEntry.expiresAt  = dimDuration and (now + dimDuration) or nil
    auraEntry.casterGuid = casterGuid
    auraEntry.writeTime  = now
    auraEntry.drStacks   = drStacks
    entry.auras[spellId] = auraEntry

    -- Schedule expiry cleanup if this aura has a duration.
    if auraEntry.expiresAt then
        ExpiryIndex:Schedule(auraEntry, targetGuid, "auras", spellId, auraEntry.expiresAt)
    end

    SpellState:MarkDirty(targetGuid)
end

-- =========================================================================
-- Aura application
-- =========================================================================

local function onAuraCast(eventName, casterGuid, targetGuid, spellId, durationMs)
    -- 1. SpellDB lookup
    local spellData = SpellDB[spellId]
    if not spellData or not spellData.trackAura then return end

    -- 2. Reject spurious events for "other" spells: the caster can never be
    -- the aura target for an enemy-targeted spell. When nampower's miss path
    -- can't find a valid hit target it falls back to casterGuid, producing
    -- AURA_CAST_ON_SELF or _OTHER with targetGuid==casterGuid for non-player
    -- casters (Kidney Shot case). Both are caught by this single equality check.
    if spellData.targetMode == "other" and targetGuid == casterGuid then
        return
    end

    -- 3. Resolve targetGuid: "self" spells use casterGuid as fallback.
    -- Note: SpellState:GetEntry(nil) hard-crashes (t[nil]=v in Lua 5.1).
    -- This guard is the safety boundary — must not be bypassed.
    if not targetGuid then
        if spellData.targetMode == "self" and casterGuid then
            targetGuid = casterGuid
        else
            return
        end
    end

    local now = GetTime()

    -- 4. Miss check (after targetGuid resolution so we compare resolved values)
    if wasMissed(casterGuid, spellId, targetGuid, now) then return end

    -- 5. Get or create entry for this target
    local entry = SpellState:GetEntry(targetGuid)

    -- 6. Duplicate-effect guard: same spell+caster within the batch window
    if isDuplicateAura(entry, spellId, casterGuid, now) then return end

    -- 7. Determine raw duration (SpellDB wins over event data)
    local rawDuration
    if spellData.duration then
        rawDuration = spellData.duration
    elseif durationMs and durationMs > 0 then
        rawDuration = durationMs / 1000
    end

    -- 8. Apply DR if applicable
    local dimDuration
    local drStacks = 0

    if rawDuration and spellData.drCat then
        dimDuration = DR:Apply(entry.dr, spellData.drCat, rawDuration, now)
        if dimDuration == 0 then
            -- Max DR stacks reached — track for DEBUFF_ADDED correction.
            addMaxStack(targetGuid, spellData.drCat)
            return
        end
        drStacks = entry.dr[spellData.drCat].stacks
    else
        dimDuration = rawDuration
    end

    -- 9. Write aura (handles old expiry, new entry, new expiry, dirty mark)
    writeAura(targetGuid, spellId, casterGuid, dimDuration, drStacks, now)
end

-- =========================================================================
-- DR drift correction handler
-- =========================================================================
-- If the server applied a debuff we thought was immune, reset DR stacks
-- and write the aura so it shows up. This prevents silent CC suppression.

onDebuffAdded = function(eventName, guid, spellId, luaSlot, stackCount)
    -- Only care about spells we track as auras with a DR category.
    local spellData = SpellDB[spellId]
    if not spellData or not spellData.trackAura or not spellData.drCat then return end

    local drCat = spellData.drCat

    -- Only correct if this GUID is actually at max stacks for this DR category.
    local catSet = maxStackGuids[drCat]
    if not catSet or not catSet[guid] then return end

    -- Server applied a debuff we thought was immune. Our DR tracking was wrong.
    -- Reset DR state for this category and write the aura at full duration.
    local now = GetTime()
    local entry = SpellState:GetEntry(guid)

    -- Reset DR: clear the category so the next DR:Apply starts fresh.
    entry.dr[drCat] = nil

    -- Apply DR fresh (starts at stack 1, full duration).
    local rawDuration = spellData.duration
    local dimDuration = rawDuration
    local drStacks = 0

    if rawDuration and drCat then
        dimDuration = DR:Apply(entry.dr, drCat, rawDuration, now)
        drStacks = entry.dr[drCat].stacks
    end

    -- Write the aura. casterGuid is nil because DEBUFF_ADDED doesn't provide it.
    writeAura(guid, spellId, nil, dimDuration, drStacks, now)

    -- This GUID is no longer at max stacks for this category.
    removeMaxStack(guid, drCat)
end

-- =========================================================================
-- Aura removal
-- =========================================================================

local function onAuraRemoved(eventName, guid, spellId, luaSlot, stackCount)
    local entry = SpellState:GetExisting(guid)
    if not entry then return end

    local oldAura = entry.auras[spellId]
    if not oldAura then return end

    ExpiryIndex:Unschedule(oldAura, guid)
    entry.auras[spellId] = nil
    SpellState:MarkDirty(guid)
end

-- =========================================================================
-- Death cleanup
-- =========================================================================
-- Clears auras and DR but preserves cooldowns — dead targets still have
-- CDs ticking.

local function onUnitDied(eventName, guid)
    local entry = SpellState:GetExisting(guid)
    if not entry then return end

    ExpiryIndex:WipeGuid(guid)
    SpellState:ClearAurasAndDR(guid)
    SpellState:MarkDirty(guid)

    -- Remove from max-stack tracking (all categories for this GUID).
    removeMaxStack(guid, nil)
end

-- =========================================================================
-- Zone-change cleanup
-- =========================================================================

-- Clear max-stack tracking state. Called on zone change.
function Auras:WipeMaxStacks()
    -- Unsubscribe from DEBUFF_ADDED_OTHER if currently subscribed.
    if maxStackTotal > 0 then
        Router:RemoveRoute("DEBUFF_ADDED_OTHER", "ANY", onDebuffAdded)
    end
    for drCat in pairs(maxStackGuids) do
        maxStackGuids[drCat] = nil
    end
    maxStackTotal = 0
end

-- =========================================================================
-- Init
-- =========================================================================

function Auras:Init()
    for spellId, entry in pairs(SpellDB) do
        if type(entry) == "table" and entry.trackAura then
            Router:AddRoute("SPELL_MISS_OTHER", spellId, onSpellMiss)
            Router:AddRoute("AURA_CAST_ON_OTHER", spellId, onAuraCast)
            Router:AddRoute("BUFF_REMOVED_OTHER", spellId, onAuraRemoved)
            Router:AddRoute("DEBUFF_REMOVED_OTHER", spellId, onAuraRemoved)
        end
    end
    Router:AddRoute("UNIT_DIED", "ANY", onUnitDied)
end
