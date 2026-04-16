-- ==========================================================================
-- features/Cooldowns.lua
-- ==========================================================================
-- Purpose:  Tracks enemy cooldowns from SPELL_GO_OTHER events.
-- Owns:     Route registrations for cooldown-tracked spells and the
--           onSpellGo handler function.
-- Does NOT: Parse raw event args (Router does that), filter by faction,
--           render frames, or manage expiry cleanup.
-- Used by:  Router dispatches SPELL_GO_OTHER to the registered handler.
--           SPELL_GO_SELF is handled via shared dispatchers in Router.
-- Calls:    AzF.SpellDB (lookup), AzF.SpellState (GetEntry, MarkDirty),
--           AzF.ExpiryIndex (Schedule, Unschedule), AzF.Router (AddRoute).
-- ==========================================================================

local SpellDB     = AzF.SpellDB
local SpellState  = AzF.SpellState
local Router      = AzF.Router
local ExpiryIndex = AzF.ExpiryIndex
local Cooldowns   = AzF.Cooldowns

-- Handle a SPELL_GO_OTHER event for a tracked cooldown spell.
-- Writes cooldown start/expiry to SpellState and processes resets.
local function onSpellGo(eventName, casterGuid, spellId, targetGuid, numTargetsHit, numTargetsMissed)
    local spellData = SpellDB[spellId]
    if not spellData then return end
    if not spellData.trackCd and not spellData.resetsSpells then return end

    -- Resolve casterGuid: "self" spells can use targetGuid as fallback because
    -- caster == target by definition. Other targetModes cannot infer the caster.
    -- Note: SpellState:GetEntry(nil) hard-crashes (t[nil]=v in Lua 5.1).
    -- This guard is the safety boundary — must not be bypassed.
    if not casterGuid then
        if spellData.targetMode == "self" and targetGuid then
            casterGuid = targetGuid
        else
            return
        end
    end

    local now = GetTime()
    local entry = SpellState:GetEntry(casterGuid)

    -- Record this spell's cooldown (only for trackCd spells).
    if spellData.trackCd and spellData.cooldown and spellData.cooldown > 0 then
        local oldCd = entry.cooldowns[spellId]
        if oldCd then
            ExpiryIndex:Unschedule(oldCd, casterGuid)
        end
        local cooldownEntry = oldCd or {}
        cooldownEntry.startedAt = now
        cooldownEntry.expiresAt = now + spellData.cooldown
        entry.cooldowns[spellId] = cooldownEntry
        ExpiryIndex:Schedule(cooldownEntry, casterGuid, "cooldowns", spellId, cooldownEntry.expiresAt)
    end

    -- If this spell resets other cooldowns, clear them.
    if spellData.resetsSpells then
        for resetId in pairs(spellData.resetsSpells) do
            local oldCd = entry.cooldowns[resetId]
            if oldCd then
                ExpiryIndex:Unschedule(oldCd, casterGuid)
            end
            entry.cooldowns[resetId] = nil
        end
    end

    SpellState:MarkDirty(casterGuid)
end

-- Register a route for every spell in SpellDB that has trackCd enabled.
function Cooldowns:Init()
    for spellId, entry in pairs(SpellDB) do
        if type(entry) == "table" and (entry.trackCd or entry.resetsSpells) then
            Router:AddRoute("SPELL_GO_OTHER", spellId, onSpellGo)
        end
    end
end
