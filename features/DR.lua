-- ==========================================================================
-- features/DR.lua
-- ==========================================================================
-- Purpose:  Pure calculator for diminishing returns. Given a DR category
--           and raw duration, returns the diminished duration.
-- Owns:     The Apply function. No state — callers pass in the dr table.
-- Does NOT: Subscribe to events, own DR state, or interact with removal.
-- Used by:  Auras handler calls DR:Apply when writing auras with a drCat.
-- Calls:    Nothing external.
-- ==========================================================================

local DR = AzF.DR

-- Reduction factors indexed by stack count.
-- Stack 1 = full duration, stack 4 = immune (0 duration).
local REDUCTION = { 1.0, 0.5, 0.25, 0 }

-- DR window in seconds. Stacks reset when the window expires.
local DR_WINDOW = 15

-- -------------------------------------------------------------------------
-- Apply: calculate diminished duration and advance DR stacks.
--
-- drState:     the entry.dr table from SpellState (keyed by drCat)
-- drCat:       string like "stun", "fear", "root"
-- rawDuration: base duration in seconds
-- now:         GetTime()
--
-- Returns: diminished duration (number). 0 means immune.
-- -------------------------------------------------------------------------
function DR:Apply(drState, drCat, rawDuration, now)
    local info = drState[drCat]

    -- No existing entry: start fresh at stack 1.
    if not info then
        drState[drCat] = { stacks = 1, windowExpires = now + DR_WINDOW }
        return rawDuration * REDUCTION[1]
    end

    -- Window expired: reuse the existing table to avoid allocation.
    if now >= info.windowExpires then
        info.stacks = 1
        info.windowExpires = now + DR_WINDOW
        return rawDuration * REDUCTION[1]
    end

    -- Already at max stacks (immune). Do not increment or refresh.
    if info.stacks >= 4 then
        return 0
    end

    -- Increment stacks and refresh window.
    info.stacks = info.stacks + 1
    info.windowExpires = now + DR_WINDOW

    return rawDuration * REDUCTION[info.stacks]
end
