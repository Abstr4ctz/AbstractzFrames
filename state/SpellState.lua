-- ==========================================================================
-- state/SpellState.lua
-- ==========================================================================
-- Purpose:  Per-GUID runtime state storage. Stores cooldowns, auras, and DR.
--           Provides entry creation, lookup, dirty marking, and cleanup.
-- Owns:     The spellState table (local), entry shape, and all accessors.
-- Does NOT: Subscribe to events, parse combat log, render frames, or own
--           expiry scheduling.
-- Used by:  Feature handlers (Cooldowns, Auras, DR).
-- Calls:    Nothing external.
-- ==========================================================================

local SpellState = AzF.SpellState

-- The runtime state table. Keyed by GUID.
-- spellState[guid] = {
--     cooldowns = {},  -- [spellId] = { startedAt, expiresAt }
--     auras     = {},  -- [spellId] = { startedAt, expiresAt, casterGuid, writeTime, drStacks }
--     dr        = {},  -- [drCat]   = { stacks, windowExpires }
--     cast      = nil, -- { spellId, startedAt, endTime, isChannel } or nil; written by features/Casts.lua
-- }
local spellState = {}

-- GUIDs whose state has changed since the last visual refresh.
-- Consumed by the Driver, which flushes dirty GUIDs to VisualSync.
local dirtyGuids = {}

-- Return the state entry for a GUID, creating it lazily if needed.
-- SpellState owns the entry shape — all buckets are created here.
function SpellState:GetEntry(guid)
    local entry = spellState[guid]
    if not entry then
        entry = {
            cooldowns = {},
            auras     = {},
            dr        = {},
        }
        spellState[guid] = entry
    end
    return entry
end

-- Return the state entry for a GUID without creating it.
-- Returns nil if no entry exists. Used by removal and death handlers
-- to avoid creating empty entries for unknown GUIDs.
function SpellState:GetExisting(guid)
    return spellState[guid]
end

-- Mark a GUID as needing a visual refresh after a state change.
function SpellState:MarkDirty(guid)
    dirtyGuids[guid] = true
end

-- Return the dirty-GUID table. The future visual driver will consume this.
function SpellState:GetDirtyGuids()
    return dirtyGuids
end

-- Clear auras and DR for one GUID. Preserves cooldowns and the GUID entry.
-- Uses for-nil pattern so existing local references to sub-tables stay valid.
function SpellState:ClearAurasAndDR(guid)
    local entry = spellState[guid]
    if not entry then return end

    for spellId in pairs(entry.auras) do
        entry.auras[spellId] = nil
    end
    for drCat in pairs(entry.dr) do
        entry.dr[drCat] = nil
    end
end

-- Return the raw spellState table. Used by ExpiryIndex:ProcessExpiries
-- to look up live entries without importing SpellState's internals.
function SpellState:GetStateTable()
    return spellState
end

-- Wipe all GUID entries and dirty marks. Safe to call on empty state.
-- Used on zone changes to prevent stale data from a previous zone.
function SpellState:Wipe()
    for guid in pairs(spellState) do
        spellState[guid] = nil
    end
    for guid in pairs(dirtyGuids) do
        dirtyGuids[guid] = nil
    end
end
