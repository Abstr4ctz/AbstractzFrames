-- ==========================================================================
-- state/ExpiryIndex.lua
-- ==========================================================================
-- Purpose:  Flat registry of timed entries (auras, cooldowns) that need
--           automatic removal when they expire.
-- Owns:     The expiryIndex table, guidExpiries reverse map, nextExpiry
--           optimization, and all schedule/unschedule/process/wipe logic.
-- Does NOT: Subscribe to events, render anything, or own spell state.
-- Used by:  Driver calls ProcessExpiries on tick. Auras and Cooldowns call
--           Schedule/Unschedule when writing or removing entries.
-- Calls:    Nothing external. Receives spellState and markDirtyFn as args.
-- ==========================================================================

local ExpiryIndex = AzF.ExpiryIndex

-- The expiry index. Keyed by entry-object (the same Lua table that lives
-- in spellState[guid].auras[spellId] or spellState[guid].cooldowns[spellId]).
-- Value: true (routing metadata stored directly on entryObject as _exGuid,
-- _exBucket, _exKey; expiresAt is already on the entry object).
local expiryIndex = {}

-- Reverse map: guidExpiries[guid] = { [entryObject] = true }
-- Enables efficient per-GUID cleanup on death.
local guidExpiries = {}

-- Optimization: the earliest known expiry time. ProcessExpiries skips the
-- full scan when nothing is due (now < nextExpiry). nil means "nothing scheduled."
local nextExpiry = nil

-- When an Unschedule might have invalidated the cached nextExpiry,
-- this flag tells ProcessExpiries to recalculate from the full index.
local nextExpiryDirty = false

-- Register a timed entry for automatic expiry cleanup.
-- Routing metadata is stored directly on entryObject to avoid a per-schedule
-- table allocation. expiresAt is already present on the entry object.
function ExpiryIndex:Schedule(entryObject, guid, bucket, key, expiresAt)
    entryObject._exGuid   = guid
    entryObject._exBucket = bucket
    entryObject._exKey    = key
    expiryIndex[entryObject] = true

    -- Add to reverse map.
    local guidSet = guidExpiries[guid]
    if not guidSet then
        guidSet = {}
        guidExpiries[guid] = guidSet
    end
    guidSet[entryObject] = true

    -- Update nextExpiry if this entry expires sooner.
    if not nextExpiry or expiresAt < nextExpiry then
        nextExpiry = expiresAt
    end
end

-- Remove a timed entry from the index.
function ExpiryIndex:Unschedule(entryObject, guid)
    if not expiryIndex[entryObject] then return end

    -- If this entry's expiresAt was at or before nextExpiry, the cached
    -- value may now be invalid.
    if nextExpiry and entryObject.expiresAt <= nextExpiry then
        nextExpiryDirty = true
    end

    expiryIndex[entryObject] = nil

    local guidSet = guidExpiries[guid]
    if guidSet then
        guidSet[entryObject] = nil
        if not next(guidSet) then
            guidExpiries[guid] = nil
        end
    end
end

-- Remove ALL expiry registrations for one GUID. Used on death cleanup.
function ExpiryIndex:WipeGuid(guid)
    local guidSet = guidExpiries[guid]
    if not guidSet then return end

    for entryObject in pairs(guidSet) do
        expiryIndex[entryObject] = nil
    end

    guidExpiries[guid] = nil
    nextExpiryDirty = true
end

-- Clear the entire index. Used on zone change.
function ExpiryIndex:Wipe()
    expiryIndex = {}
    guidExpiries = {}
    nextExpiry = nil
    nextExpiryDirty = false
end

-- Process expired entries and remove them from spell state.
-- Called by the Driver every 0.05s.
--
-- spellState:   the raw spellState table (from SpellState:GetStateTable())
-- markDirtyFn:  function(guid) to mark a GUID for visual refresh
function ExpiryIndex:ProcessExpiries(now, spellState, markDirtyFn)
    -- Recalculate nextExpiry if a previous Unschedule invalidated it.
    if nextExpiryDirty then
        nextExpiry = nil
        for entryObject in pairs(expiryIndex) do
            local exp = entryObject.expiresAt
            if not nextExpiry or exp < nextExpiry then
                nextExpiry = exp
            end
        end
        nextExpiryDirty = false
    end

    -- Fast path: nothing scheduled, or nothing is due yet.
    if not nextExpiry or now < nextExpiry then return end

    -- Reset nextExpiry — we will recalculate it from surviving entries.
    nextExpiry = nil

    -- Iterating with pairs() while setting keys to nil is safe in Lua 5.1.
    for entryObject in pairs(expiryIndex) do
        local exp = entryObject.expiresAt
        if exp <= now then
            local guid   = entryObject._exGuid
            local bucket = entryObject._exBucket
            local key    = entryObject._exKey

            -- Look up the live state entry.
            local guidState = spellState[guid]
            if guidState then
                local bucketTable = guidState[bucket]
                if bucketTable then
                    -- Only remove if the live entry is the SAME object as the
                    -- one we registered. If an aura/cooldown was overwritten
                    -- (new object at the same key), the old registration is
                    -- stale — just clean up the index entry.
                    if bucketTable[key] == entryObject then
                        bucketTable[key] = nil
                        markDirtyFn(guid)
                    end
                end
            end

            -- Remove from the index and reverse map.
            expiryIndex[entryObject] = nil
            local guidSet = guidExpiries[guid]
            if guidSet then
                guidSet[entryObject] = nil
                if not next(guidSet) then
                    guidExpiries[guid] = nil
                end
            end
        else
            -- Entry not yet expired — track the smallest expiresAt.
            if not nextExpiry or exp < nextExpiry then
                nextExpiry = exp
            end
        end
    end
end
