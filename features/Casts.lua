-- ==========================================================================
-- features/Casts.lua
-- ==========================================================================
-- Purpose:  Tracks active enemy casts and channels from spell-start events.
-- Owns:     SPELL_START_OTHER, SPELL_GO_OTHER, SPELL_FAILED_OTHER, and
--           UNIT_DIED route registrations; entry.cast state writes.
-- Does NOT: Render anything, own spell metadata, or track cooldowns/auras.
-- Used by:  Router dispatches to handlers registered in Init().
-- Calls:    AzF.SpellState (GetEntry, GetExisting, MarkDirty),
--           AzF.Router (AddRoute). WoW API: GetTime.
-- ==========================================================================

local Casts      = AzF.Casts
local SpellState = AzF.SpellState
local Router     = AzF.Router

local SPELLTYPE_CHANNEL    = 1
local SPELLTYPE_AUTOREPEAT = 2

-- Active cast tracking for timer-based expiry.
local activeCasts = {}  -- [guid] = endTime
local nextCastExpiry = nil
local nextCastExpiryDirty = false

-- Local free-list for cast entry tables. Avoids per-cast table allocation
-- in steady state. Public contract (entry.cast = nil means no active cast)
-- is preserved unchanged.
local castFreeList  = {}
local castFreeCount = 0

local function AcquireCast()
    if castFreeCount > 0 then
        local t = castFreeList[castFreeCount]
        castFreeList[castFreeCount] = nil
        castFreeCount = castFreeCount - 1
        return t
    end
    return {}
end

local function ReleaseCast(t)
    castFreeCount = castFreeCount + 1
    castFreeList[castFreeCount] = t
end

local function InvalidateNextCastExpiryIfNeeded(endTime)
    if endTime and nextCastExpiry and endTime <= nextCastExpiry then
        nextCastExpiryDirty = true
    end
end

local function RecalculateNextCastExpiry()
    nextCastExpiry = nil
    for _, endTime in pairs(activeCasts) do
        if not nextCastExpiry or endTime < nextCastExpiry then
            nextCastExpiry = endTime
        end
    end
    nextCastExpiryDirty = false
end

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

local function onSpellStart(eventName, casterGuid, spellId, targetGuid, castTimeMs, channelDurationMs, spellType)
    -- Ignore autorepeating (wand shots).
    if spellType == SPELLTYPE_AUTOREPEAT then return end
    if not casterGuid then return end

    local isChannel  = (spellType == SPELLTYPE_CHANNEL)
    local durationMs = isChannel and channelDurationMs or castTimeMs
    if not durationMs or durationMs <= 0 then return end

    local now   = GetTime()
    local endTime = now + durationMs / 1000
    local oldEndTime = activeCasts[casterGuid]
    local entry = SpellState:GetEntry(casterGuid)

    -- Release old cast table if overwriting (new cast before old finished).
    if entry.cast then
        ReleaseCast(entry.cast)
    end

    local cast = AcquireCast()
    cast.spellId   = spellId
    cast.startedAt = now
    cast.endTime   = endTime
    cast.isChannel = isChannel
    entry.cast = cast

    InvalidateNextCastExpiryIfNeeded(oldEndTime)
    activeCasts[casterGuid] = endTime
    if not nextCastExpiry or endTime < nextCastExpiry then
        nextCastExpiry = endTime
    end
    SpellState:MarkDirty(casterGuid)
end

local function onSpellGo(eventName, casterGuid, spellId, targetGuid, numTargetsHit, numTargetsMissed)
    if not casterGuid then return end

    local entry = SpellState:GetExisting(casterGuid)
    if not entry or not entry.cast then return end

    -- Channels fire SPELL_GO at launch while the channel continues.
    -- Only clear non-channel casts on completion.
    if entry.cast.isChannel then return end
    if entry.cast.spellId ~= spellId then return end

    InvalidateNextCastExpiryIfNeeded(activeCasts[casterGuid])
    ReleaseCast(entry.cast)
    entry.cast = nil
    activeCasts[casterGuid] = nil
    SpellState:MarkDirty(casterGuid)
end

local function onSpellFailed(eventName, casterGuid, spellId)
    if not casterGuid then return end

    local entry = SpellState:GetExisting(casterGuid)
    if not entry or not entry.cast then return end
    if entry.cast.spellId ~= spellId then return end

    InvalidateNextCastExpiryIfNeeded(activeCasts[casterGuid])
    ReleaseCast(entry.cast)
    entry.cast = nil
    activeCasts[casterGuid] = nil
    SpellState:MarkDirty(casterGuid)
end

local function onUnitDied(eventName, guid)
    if not guid then return end

    InvalidateNextCastExpiryIfNeeded(activeCasts[guid])
    activeCasts[guid] = nil
    local entry = SpellState:GetExisting(guid)
    if not entry or not entry.cast then return end

    ReleaseCast(entry.cast)
    entry.cast = nil
    SpellState:MarkDirty(guid)
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Casts:Init()
    Router:AddRoute("SPELL_START_OTHER", "ANY", onSpellStart)
    Router:AddRoute("SPELL_GO_OTHER",    "ANY", onSpellGo)
    Router:AddRoute("SPELL_FAILED_OTHER","ANY", onSpellFailed)
    Router:AddRoute("UNIT_DIED",         "ANY", onUnitDied)
end

-- ---------------------------------------------------------------------------
-- Timer-based expiry
-- ---------------------------------------------------------------------------

-- Clear expired casts from SpellState. Called by Driver each tick.
function Casts:ProcessExpiries(now)
    if nextCastExpiryDirty then
        RecalculateNextCastExpiry()
    end

    if not nextCastExpiry or now < nextCastExpiry then
        return
    end

    local nextActiveExpiry = nil
    for guid, endTime in pairs(activeCasts) do
        if endTime <= now then
            activeCasts[guid] = nil
            local entry = SpellState:GetExisting(guid)
            if entry and entry.cast then
                ReleaseCast(entry.cast)
                entry.cast = nil
                SpellState:MarkDirty(guid)
            end
        elseif not nextActiveExpiry or endTime < nextActiveExpiry then
            nextActiveExpiry = endTime
        end
    end

    nextCastExpiry = nextActiveExpiry
end

-- Clear all active cast tracking. Called on zone-change wipe.
function Casts:Wipe()
    for k in pairs(activeCasts) do
        activeCasts[k] = nil
    end
    nextCastExpiry = nil
    nextCastExpiryDirty = false
    -- Reset free-list (entries are orphaned after SpellState:Wipe).
    for i = 1, castFreeCount do
        castFreeList[i] = nil
    end
    castFreeCount = 0
end
