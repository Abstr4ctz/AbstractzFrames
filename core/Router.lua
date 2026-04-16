-- ==========================================================================
-- core/Router.lua
-- ==========================================================================
-- Purpose:  Routes raw WoW combat events to registered handlers with
--           clean, normalized arguments. Only module that reads arg1..arg9.
-- Owns:     Route table, dispatcher functions, EventBus lifecycle for
--           combat events.
-- Does NOT: Look up SpellDB/SpellRules, filter enemies/friendlies, write
--           to state tables, touch frames or rendering.
-- Used by:  Feature handlers register routes to receive normalized data.
-- Calls:    AzF.EventBus (Subscribe/Unsubscribe).
-- ==========================================================================

local Router = AzF.Router
local EventBus = AzF.EventBus

-- Route table: routes[eventName][spellId] = { [1]=handler, ..., n=count }
-- The special key "ANY" matches all spellIds for an event.
local routes = {}

-- Dispatcher functions keyed by event name. AddRoute/RemoveRoute use this
-- to subscribe/unsubscribe the correct function to EventBus.
local dispatchers = {}

-- When false, no dispatchers are subscribed to EventBus. Routes are still
-- registered so Enable() can restore subscriptions later.
local enabled = true

-- Pending removals deferred because a dispatcher for this event is running.
-- Same safety pattern as EventBus: if a handler calls RemoveRoute during
-- dispatch, the removal is queued and applied after the dispatch finishes.
-- pendingRemovals[eventName] = { {spellIdOrANY, handler}, ..., n=count }
local pendingRemovals = {}

-- Tracks dispatch depth per event. Only flush pending removals when depth
-- hits zero. Matches the same pattern used in EventBus.
local dispatchDepth = {}

-- Maps each _OTHER event to its _SELF sibling. _SELF events have identical
-- arg layouts to their _OTHER counterparts, so they reuse the same dispatcher.
-- SPELL_FAILED_SELF is excluded — it has different args than SPELL_FAILED_OTHER.
local SELF_SIBLINGS = {
    ["SPELL_GO_OTHER"]       = "SPELL_GO_SELF",
    ["SPELL_START_OTHER"]    = "SPELL_START_SELF",
    ["SPELL_MISS_OTHER"]     = "SPELL_MISS_SELF",
    ["AURA_CAST_ON_OTHER"]   = "AURA_CAST_ON_SELF",
    ["BUFF_REMOVED_OTHER"]   = "BUFF_REMOVED_SELF",
    ["DEBUFF_REMOVED_OTHER"] = "DEBUFF_REMOVED_SELF",
}

-- Normalize invalid GUIDs to nil at the dispatch boundary.
-- Downstream code only needs to check for nil, never "" or "unknown".
-- "0x0000000000000000" is nampower's sentinel for "no target" in SPELL_GO
-- and SPELL_START events.
local function NormalizeGuid(guid)
    if guid == "" or guid == "unknown" or guid == "0x0000000000000000" then
        return nil
    end
    return guid
end

-- -------------------------------------------------------------------------
-- FlushPending: apply deferred removals after dispatch finishes for an event.
-- -------------------------------------------------------------------------
local function FlushPending(eventName)
    local pending = pendingRemovals[eventName]
    if not pending then return end
    pendingRemovals[eventName] = nil

    for i = 1, pending.n do
        local entry = pending[i]
        Router:RemoveRoute(eventName, entry[1], entry[2])
    end
end

-- -------------------------------------------------------------------------
-- DispatchRoutes: shared normalized route fan-out used by both live WoW
-- event dispatchers and synthetic test injections.
-- routeKey is usually a spellId; nil means "ANY handlers only".
-- -------------------------------------------------------------------------
local function DispatchRoutes(eventName, routeKey, a1, a2, a3, a4, a5, a6)
    local eventRoutes = routes[eventName]
    if not eventRoutes then return end

    dispatchDepth[eventName] = (dispatchDepth[eventName] or 0) + 1

    if routeKey ~= nil then
        local routeHandlers = eventRoutes[routeKey]
        if routeHandlers then
            for i = 1, routeHandlers.n do
                routeHandlers[i](eventName, a1, a2, a3, a4, a5, a6)
            end
        end
    end

    local anyHandlers = eventRoutes["ANY"]
    if anyHandlers then
        for i = 1, anyHandlers.n do
            anyHandlers[i](eventName, a1, a2, a3, a4, a5, a6)
        end
    end

    dispatchDepth[eventName] = dispatchDepth[eventName] - 1
    if dispatchDepth[eventName] == 0 then
        dispatchDepth[eventName] = nil
        FlushPending(eventName)
    end
end

-- =========================================================================
-- Dispatchers
-- =========================================================================
-- Each dispatcher reads raw WoW event args (arg1..arg9), extracts the
-- relevant fields, and calls registered handlers with normalized arguments.
-- =========================================================================

-- -------------------------------------------------------------------------
-- SPELL_GO_OTHER
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=itemId, arg2=spellId, arg3=casterGuid, arg4=targetGuid,
--           arg5=castFlags, arg6=numTargetsHit, arg7=numTargetsMissed
--
-- Handler receives:
--   (eventName, casterGuid, spellId, targetGuid, numTargetsHit, numTargetsMissed)
--
-- Route lookup key: spellId (arg2)
-- -------------------------------------------------------------------------
local function DispatchSpellGoOther()
    local spellId = arg2
    local casterGuid = NormalizeGuid(arg3)
    local targetGuid = NormalizeGuid(arg4)
    local numTargetsHit = arg6
    local numTargetsMissed = arg7
    DispatchRoutes("SPELL_GO_OTHER", spellId, casterGuid, spellId, targetGuid, numTargetsHit, numTargetsMissed)
end

-- -------------------------------------------------------------------------
-- SPELL_START_OTHER
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=itemId, arg2=spellId, arg3=casterGuid, arg4=targetGuid,
--           arg5=castFlags, arg6=castTimeMs, arg7=channelDurationMs,
--           arg8=spellType
--
-- Handler receives:
--   (eventName, casterGuid, spellId, targetGuid, castTimeMs, channelDurationMs, spellType)
--
-- Route lookup key: spellId (arg2)
-- -------------------------------------------------------------------------
local function DispatchSpellStartOther()
    local spellId = arg2
    local casterGuid = NormalizeGuid(arg3)
    local targetGuid = NormalizeGuid(arg4)
    local castTimeMs = arg6
    local channelDurationMs = arg7
    local spellType = arg8
    DispatchRoutes("SPELL_START_OTHER", spellId, casterGuid, spellId, targetGuid, castTimeMs, channelDurationMs, spellType)
end

-- -------------------------------------------------------------------------
-- SPELL_FAILED_OTHER
-- ARG LAYOUT: verified.
--
-- WARNING: Different arg layout than SPELL_GO/SPELL_START.
-- Raw args: arg1=casterGuid, arg2=spellId
--
-- Handler receives:
--   (eventName, casterGuid, spellId)
--
-- Route lookup key: spellId (arg2)
-- -------------------------------------------------------------------------
local function DispatchSpellFailedOther()
    local casterGuid = NormalizeGuid(arg1)
    local spellId = arg2
    DispatchRoutes("SPELL_FAILED_OTHER", spellId, casterGuid, spellId)
end

-- -------------------------------------------------------------------------
-- SPELL_MISS_OTHER
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=casterGuid, arg2=targetGuid, arg3=spellId, arg4=missInfo
--
-- Handler receives:
--   (eventName, casterGuid, targetGuid, spellId, missInfo)
--
-- Route lookup key: spellId (arg3)
-- -------------------------------------------------------------------------
local function DispatchSpellMissOther()
    local casterGuid = NormalizeGuid(arg1)
    local targetGuid = NormalizeGuid(arg2)
    local spellId = arg3
    local missInfo = arg4
    DispatchRoutes("SPELL_MISS_OTHER", spellId, casterGuid, targetGuid, spellId, missInfo)
end

-- -------------------------------------------------------------------------
-- AURA_CAST_ON_OTHER
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=spellId, arg2=casterGuid, arg3=targetGuid, arg4=effect,
--           arg5=effectAuraName, arg6=effectAmplitude, arg7=effectMiscValue,
--           arg8=durationMs, arg9=auraCapStatus
--
-- Only casterGuid, targetGuid, spellId, and durationMs are forwarded.
-- The raw effect/amplitude/miscValue fields are not passed to handlers —
-- they can be added later if a handler needs them.
--
-- Handler receives:
--   (eventName, casterGuid, targetGuid, spellId, durationMs)
--
-- Route lookup key: spellId (arg1)
-- -------------------------------------------------------------------------
local function DispatchAuraCastOnOther()
    local spellId = arg1
    local casterGuid = NormalizeGuid(arg2)
    local targetGuid = NormalizeGuid(arg3)
    local durationMs = arg8
    DispatchRoutes("AURA_CAST_ON_OTHER", spellId, casterGuid, targetGuid, spellId, durationMs)
end

-- -------------------------------------------------------------------------
-- Aura event factory for BUFF_REMOVED_OTHER, DEBUFF_REMOVED_OTHER, and
-- DEBUFF_ADDED_OTHER. These events share the same arg layout, so a factory
-- creates all dispatchers to avoid duplicating the same code.
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=guid, arg2=luaSlot, arg3=spellId, arg4=stackCount
--
-- Handler receives:
--   (eventName, guid, spellId, luaSlot, stackCount)
--
-- Route lookup key: spellId (arg3)
-- -------------------------------------------------------------------------
local function CreateAuraEventDispatcher(eventName)
    return function()
        local guid = NormalizeGuid(arg1)
        local luaSlot = arg2
        local spellId = arg3
        local stackCount = arg4
        DispatchRoutes(eventName, spellId, guid, spellId, luaSlot, stackCount)
    end
end

local DispatchBuffRemovedOther = CreateAuraEventDispatcher("BUFF_REMOVED_OTHER")
local DispatchDebuffRemovedOther = CreateAuraEventDispatcher("DEBUFF_REMOVED_OTHER")
local DispatchDebuffAddedOther = CreateAuraEventDispatcher("DEBUFF_ADDED_OTHER")

-- -------------------------------------------------------------------------
-- UNIT_DIED
-- ARG LAYOUT: verified.
--
-- Raw args: arg1=guid
--
-- This event has no spellId. Only "ANY" handlers are called.
--
-- Handler receives:
--   (eventName, guid)
--
-- Route lookup: ANY only (no spell-specific routing)
-- -------------------------------------------------------------------------
local function DispatchUnitDied()
    local guid = NormalizeGuid(arg1)
    DispatchRoutes("UNIT_DIED", nil, guid)
end

-- -------------------------------------------------------------------------
-- Dispatcher registry: maps event names to their dispatcher functions.
-- AddRoute and RemoveRoute use this to subscribe/unsubscribe from EventBus.
-- -------------------------------------------------------------------------
dispatchers["SPELL_GO_OTHER"]       = DispatchSpellGoOther
dispatchers["SPELL_START_OTHER"]    = DispatchSpellStartOther
dispatchers["SPELL_FAILED_OTHER"]   = DispatchSpellFailedOther
dispatchers["SPELL_MISS_OTHER"]     = DispatchSpellMissOther
dispatchers["AURA_CAST_ON_OTHER"]   = DispatchAuraCastOnOther
dispatchers["BUFF_REMOVED_OTHER"]   = DispatchBuffRemovedOther
dispatchers["DEBUFF_REMOVED_OTHER"] = DispatchDebuffRemovedOther
dispatchers["DEBUFF_ADDED_OTHER"]   = DispatchDebuffAddedOther
dispatchers["UNIT_DIED"]            = DispatchUnitDied

-- =========================================================================
-- Public API
-- =========================================================================

-- -------------------------------------------------------------------------
-- AddRoute: register a handler for a specific event + spellId (or "ANY").
--
-- eventName:      string, e.g. "SPELL_GO_OTHER"
-- spellIdOrANY:   number (spellId) or the string "ANY"
-- handler:        function to call when the event fires for this spell
--
-- If this is the first route for this eventName, the dispatcher is
-- subscribed to EventBus (lazy activation).
-- Idempotent — adding the same handler twice for the same event+spell
-- is a no-op.
-- -------------------------------------------------------------------------
function Router:AddRoute(eventName, spellIdOrANY, handler)
    local eventRoutes = routes[eventName]

    if not eventRoutes then
        -- First route for this event: create the table. Only subscribe
        -- the dispatcher to EventBus if the Router is currently enabled.
        -- When disabled, routes are still registered so Enable() can
        -- subscribe all dispatchers later.
        eventRoutes = {}
        routes[eventName] = eventRoutes

        if enabled then
            EventBus:Subscribe(eventName, dispatchers[eventName])

            -- Also subscribe the same dispatcher to the _SELF sibling event
            -- (if one exists). _SELF events have identical arg layouts, so the
            -- same dispatcher handles both.
            local selfEvent = SELF_SIBLINGS[eventName]
            if selfEvent then
                EventBus:Subscribe(selfEvent, dispatchers[eventName])
            end
        end
    end

    local key = spellIdOrANY
    local handlerList = eventRoutes[key]

    if not handlerList then
        handlerList = { n = 0 }
        eventRoutes[key] = handlerList
    end

    -- Idempotent: adding the same handler twice is a no-op.
    for i = 1, handlerList.n do
        if handlerList[i] == handler then
            return
        end
    end

    handlerList.n = handlerList.n + 1
    handlerList[handlerList.n] = handler
end

-- -------------------------------------------------------------------------
-- RemoveRoute: unregister a handler for a specific event + spellId (or "ANY").
--
-- Uses swap-remove: the removed handler is swapped with the last entry in
-- the list, then the list is shrunk. This avoids shifting elements.
--
-- If a dispatcher for this event is currently running, the removal is
-- deferred until dispatch finishes. Same safety pattern as EventBus.
--
-- If the handler list for a spellId becomes empty, that key is removed.
-- If the entire event table becomes empty, the dispatcher is unsubscribed
-- from EventBus (lazy deactivation).
-- Idempotent — removing a handler that is not registered is a no-op.
-- -------------------------------------------------------------------------
function Router:RemoveRoute(eventName, spellIdOrANY, handler)
    local eventRoutes = routes[eventName]
    if not eventRoutes then return end

    local key = spellIdOrANY
    local handlerList = eventRoutes[key]
    if not handlerList then return end

    -- If a dispatcher for this event is running, defer the removal.
    if (dispatchDepth[eventName] or 0) > 0 then
        local pending = pendingRemovals[eventName]
        if not pending then
            pending = { n = 0 }
            pendingRemovals[eventName] = pending
        end
        pending.n = pending.n + 1
        pending[pending.n] = { key, handler }
        return
    end

    -- Find and swap-remove the handler.
    for i = 1, handlerList.n do
        if handlerList[i] == handler then
            handlerList[i] = handlerList[handlerList.n]
            handlerList[handlerList.n] = nil
            handlerList.n = handlerList.n - 1

            -- If no handlers remain for this spell, remove the key.
            if handlerList.n == 0 then
                eventRoutes[key] = nil

                -- If no routes remain for this event, unsubscribe from EventBus.
                if not next(eventRoutes) then
                    routes[eventName] = nil
                    EventBus:Unsubscribe(eventName, dispatchers[eventName])

                    -- Also unsubscribe from the _SELF sibling if one exists.
                    local selfEvent = SELF_SIBLINGS[eventName]
                    if selfEvent then
                        EventBus:Unsubscribe(selfEvent, dispatchers[eventName])
                    end
                end
            end

            return
        end
    end
end

-- =========================================================================
-- Enable / Disable
-- =========================================================================
-- Bulk-manage EventBus subscriptions for all active dispatchers. When
-- disabled, zero combat events are processed (EventBus never calls
-- dispatchers). Routes remain registered so Enable() can restore them.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Disable: unsubscribe all dispatchers from EventBus.
-- -------------------------------------------------------------------------
function Router:Disable()
    if not enabled then return end
    enabled = false

    for eventName, _ in pairs(routes) do
        EventBus:Unsubscribe(eventName, dispatchers[eventName])

        local selfEvent = SELF_SIBLINGS[eventName]
        if selfEvent then
            EventBus:Unsubscribe(selfEvent, dispatchers[eventName])
        end
    end
end

-- -------------------------------------------------------------------------
-- Enable: re-subscribe all dispatchers to EventBus.
-- -------------------------------------------------------------------------
function Router:Enable()
    if enabled then return end
    enabled = true

    for eventName, _ in pairs(routes) do
        EventBus:Subscribe(eventName, dispatchers[eventName])

        local selfEvent = SELF_SIBLINGS[eventName]
        if selfEvent then
            EventBus:Subscribe(selfEvent, dispatchers[eventName])
        end
    end
end

-- -------------------------------------------------------------------------
-- Inject: dispatch a synthetic normalized combat event through the same
-- Router routes used by live combat. This bypasses EventBus subscriptions
-- and the Router enabled/disabled gate on purpose so the testing harness can
-- exercise feature pipelines even when live combat tracking is zone-gated.
-- -------------------------------------------------------------------------
function Router:Inject(eventName, a1, a2, a3, a4, a5, a6)
    local routeKey = nil

    if eventName == "SPELL_GO_OTHER" or eventName == "SPELL_START_OTHER" then
        a1 = NormalizeGuid(a1)
        a3 = NormalizeGuid(a3)
        routeKey = a2
    elseif eventName == "SPELL_FAILED_OTHER" then
        a1 = NormalizeGuid(a1)
        routeKey = a2
    elseif eventName == "SPELL_MISS_OTHER" then
        a1 = NormalizeGuid(a1)
        a2 = NormalizeGuid(a2)
        routeKey = a3
    elseif eventName == "AURA_CAST_ON_OTHER" then
        a1 = NormalizeGuid(a1)
        a2 = NormalizeGuid(a2)
        routeKey = a3
    elseif eventName == "BUFF_REMOVED_OTHER"
        or eventName == "DEBUFF_REMOVED_OTHER"
        or eventName == "DEBUFF_ADDED_OTHER" then
        a1 = NormalizeGuid(a1)
        routeKey = a2
    elseif eventName == "UNIT_DIED" then
        a1 = NormalizeGuid(a1)
    else
        return nil, "unsupported event"
    end

    DispatchRoutes(eventName, routeKey, a1, a2, a3, a4, a5, a6)
    return true
end
