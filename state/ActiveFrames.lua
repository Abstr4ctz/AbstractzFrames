-- ==========================================================================
-- state/ActiveFrames.lua
-- ==========================================================================
-- Purpose:  Tracks which GUIDs currently have visible UI destinations.
--           Each GUID can have at most one of each: nameplate, target,
--           focus, arena slot.
-- Owns:     The activeFrames table and all slot manipulation helpers.
-- Does NOT: Subscribe to events, render anything, or know about spell state.
-- Used by:  Target binding sets/clears the target slot. VisualSync reads
--           entries to route updates to the correct destination.
-- Calls:    Nothing external.
-- ==========================================================================

local ActiveFrames = AzF.ActiveFrames

-- The active frames table. Keyed by GUID.
-- activeFrames[guid] = {
--     nameplate = nil,    -- plate tag string or nil
--     arena = nil,        -- slot number (1/2/3) or nil
--     target = nil,       -- true or nil
--     focus = nil,        -- true or nil
--     count = 0,          -- number of active slots
-- }
local activeFrames = {}

local freeEntries = {}
local freeCount   = 0

-- Set a slot for a GUID. Manages count and auto-cleanup.
function ActiveFrames:SetSlot(guid, slot, value)
    local entry = activeFrames[guid]

    if not entry then
        if value == nil then return end
        if freeCount > 0 then
            entry = freeEntries[freeCount]
            freeEntries[freeCount] = nil
            freeCount = freeCount - 1
        else
            entry = { nameplate = nil, arena = nil, target = nil, focus = nil, count = 0 }
        end
        activeFrames[guid] = entry
    end

    local oldValue = entry[slot]

    if oldValue == nil and value ~= nil then
        entry[slot] = value
        entry.count = entry.count + 1
    elseif oldValue ~= nil and value == nil then
        entry[slot] = nil
        entry.count = entry.count - 1
        if entry.count == 0 then
            activeFrames[guid] = nil
            freeCount = freeCount + 1
            freeEntries[freeCount] = entry
        end
    elseif oldValue ~= value then
        entry[slot] = value
    end
end

-- Shorthand for clearing a slot.
function ActiveFrames:ClearSlot(guid, slot)
    self:SetSlot(guid, slot, nil)
end

-- Return the entry for a GUID, or nil if not tracked.
function ActiveFrames:GetEntry(guid)
    return activeFrames[guid]
end

-- Clear all entries and free-list. Used on zone change.
function ActiveFrames:Wipe()
    for guid in pairs(activeFrames) do
        activeFrames[guid] = nil
    end
    for i = 1, freeCount do
        freeEntries[i] = nil
    end
    freeCount = 0
end
