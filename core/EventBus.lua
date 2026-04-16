-- ==========================================================================
-- core/EventBus.lua
-- ==========================================================================
-- Purpose:  Single-frame WoW event multiplexer. Lets any module subscribe
--           handlers to WoW events without touching frames directly.
-- Owns:     One hidden frame, the subscriber registry, and dispatch logic.
-- Does NOT: Fire synthetic events, provide debug/trace tools, or manage
--           addon-level lifecycle beyond raw WoW events.
-- Used by:  Any module that needs to react to WoW events.
-- Calls:    WoW API (CreateFrame, RegisterEvent, UnregisterEvent).
-- ==========================================================================

local EventBus = AzF.EventBus

-- Registry: eventName -> { [1]=handler, [2]=handler, ..., n=count }
local registry = {}

-- Pending removals deferred because dispatch is in progress for that event.
-- Key = eventName, value = { [handler] = true }
local pendingRemovals = {}

-- Tracks reentrant dispatch depth per event. Only flush when depth hits zero.
local dispatchDepth = {}

-- The single hidden frame that owns all WoW event registrations.
local frame = CreateFrame("Frame", "AzFEventBusFrame", UIParent)

-- -------------------------------------------------------------------------
-- Subscribe: register a handler for a WoW event.
-- Idempotent -- subscribing the same handler twice is a no-op.
-- -------------------------------------------------------------------------
function EventBus:Subscribe(eventName, handler)
    local list = registry[eventName]

    if not list then
        -- First subscriber for this event: create the list and register.
        list = { handler, n = 1 }
        registry[eventName] = list
        frame:RegisterEvent(eventName)
        return
    end

    -- Check for duplicate.
    for i = 1, list.n do
        if list[i] == handler then
            return
        end
    end

    list.n = list.n + 1
    list[list.n] = handler
end

-- -------------------------------------------------------------------------
-- Unsubscribe: remove a handler for a WoW event.
-- Idempotent -- unsubscribing a handler that is not registered is a no-op.
-- If dispatch is in progress for this event, removal is deferred.
-- -------------------------------------------------------------------------
function EventBus:Unsubscribe(eventName, handler)
    local list = registry[eventName]
    if not list then
        return
    end

    -- If we are currently dispatching this event, defer the removal.
    if (dispatchDepth[eventName] or 0) > 0 then
        local pending = pendingRemovals[eventName]
        if not pending then
            pending = {}
            pendingRemovals[eventName] = pending
        end
        pending[handler] = true
        return
    end

    -- Swap-remove: find the handler, swap with last, shrink list.
    for i = 1, list.n do
        if list[i] == handler then
            list[i] = list[list.n]
            list[list.n] = nil
            list.n = list.n - 1

            -- If no subscribers remain, unregister the WoW event.
            if list.n == 0 then
                registry[eventName] = nil
                frame:UnregisterEvent(eventName)
            end
            return
        end
    end
end

-- -------------------------------------------------------------------------
-- FlushPending: apply deferred removals after dispatch finishes.
-- -------------------------------------------------------------------------
local function FlushPending(eventName)
    local pending = pendingRemovals[eventName]
    if not pending then
        return
    end
    pendingRemovals[eventName] = nil

    for handler in pairs(pending) do
        EventBus:Unsubscribe(eventName, handler)
    end
end

-- -------------------------------------------------------------------------
-- OnEvent: the frame's event handler. Dispatches to all subscribers.
-- -------------------------------------------------------------------------
frame:SetScript("OnEvent", function()
    -- In Vanilla 1.12, the frame OnEvent handler receives event info
    -- through the globals: event, arg1, arg2, ...
    local currentEvent = event

    local list = registry[currentEvent]
    if not list then
        return
    end

    dispatchDepth[currentEvent] = (dispatchDepth[currentEvent] or 0) + 1

    for i = 1, list.n do
        list[i](currentEvent, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end

    dispatchDepth[currentEvent] = dispatchDepth[currentEvent] - 1

    if dispatchDepth[currentEvent] == 0 then
        dispatchDepth[currentEvent] = nil
        FlushPending(currentEvent)
    end
end)
