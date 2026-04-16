-- ==========================================================================
-- testing/Mock.lua
-- ==========================================================================
-- Purpose:  Standalone slash-command harness for simulating normalized
--           combat outcomes without real PvP interactions.
-- Owns:     Slash command parsing, unit/spell resolution, and translation
--           from test scenarios to Router:Inject() calls.
-- Does NOT: Parse raw Blizzard event args, mutate SpellState directly, or
--           duplicate feature logic.
-- ==========================================================================

local Mock    = AzF.Mock
local Router  = AzF.Router
local SpellDB = AzF.SpellDB
local Slash   = AzF.Slash

local SPELLTYPE_NORMAL  = 0
local SPELLTYPE_CHANNEL = 1

local DEFAULT_CAST_MS    = 2500
local DEFAULT_CHANNEL_MS = 3000

local initialized = false

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[AzF Mock]|r " .. message)
end

local function SpellLabel(spellId, spellData)
    if spellData and spellData.name and spellData.name ~= "" then
        return spellData.name .. " (" .. spellId .. ")"
    end
    return "Spell " .. spellId
end

local function Tokenize(message)
    local tokens = {}
    local count = 0

    for token in string.gfind(message, "%S+") do
        count = count + 1
        tokens[count] = token
    end

    return tokens, count
end

local function ResolveGuid(token)
    if not token then
        return nil, "missing unit"
    end

    local lower = string.lower(token)
    if lower == "none" or lower == "nil" then
        return nil
    end

    if string.sub(lower, 1, 5) == "guid:" then
        local guid = string.sub(token, 6)
        if guid == "" then
            return nil, "guid: requires a GUID value"
        end
        return guid
    end

    if lower ~= "target" and lower ~= "player" then
        return nil, "unknown unit '" .. token .. "' (use target, player, none, or guid:<GUID>)"
    end

    if not UnitExists(lower) then
        return nil, "'" .. lower .. "' does not exist right now"
    end

    local guid = GetUnitGUID(lower)
    if not guid or guid == "" or guid == "0x0000000000000000" then
        return nil, "'" .. lower .. "' has no GUID"
    end

    return guid
end

local function ResolveTrackedSpell(token)
    local spellId = tonumber(token)
    if not spellId then
        return nil, nil, "spellId must be numeric"
    end

    local spellData = SpellDB[spellId]
    if not spellData then
        return nil, nil, "spellId " .. spellId .. " is not in SpellDB"
    end

    return spellId, spellData
end

local function ResolveAnySpell(token)
    local spellId = tonumber(token)
    if not spellId then
        return nil, nil, "spellId must be numeric"
    end
    return spellId, SpellDB[spellId]
end

local function ParseOptionalTarget(tokens, index, count, keyword)
    if index > count then
        return nil, nil, index
    end

    if string.lower(tokens[index]) ~= keyword then
        return nil, nil, index
    end

    if index + 1 > count then
        return nil, "expected a unit after '" .. keyword .. "'", index
    end

    return tokens[index + 1], nil, index + 2
end

local function ParseDurationMs(token, fallback)
    if not token then
        return fallback
    end

    local durationMs = tonumber(token)
    if not durationMs or durationMs <= 0 then
        return nil, "duration must be a positive number of milliseconds"
    end

    return durationMs
end

local function ApplyAura(spellId, spellData, casterGuid, targetGuid)
    if not spellData.trackAura then
        return nil, "Spell does not track an aura"
    end

    local durationMs = nil
    if spellData.duration and spellData.duration > 0 then
        durationMs = spellData.duration * 1000
    end

    if spellData.targetMode == "self" then
        local selfGuid = casterGuid or targetGuid
        if not selfGuid then
            return nil, "Self-target aura needs a source or destination unit"
        end

        Router:Inject("AURA_CAST_ON_OTHER", selfGuid, nil, spellId, durationMs)
        return true
    end

    if not targetGuid then
        return nil, "Aura application needs a destination unit"
    end

    Router:Inject("AURA_CAST_ON_OTHER", casterGuid, targetGuid, spellId, durationMs)
    return true
end

local function UseSpell(spellId, spellData, casterGuid, targetGuid)
    if not spellData.trackCd and not spellData.resetsSpells then
        return nil, "Spell does not track a cooldown or reset"
    end

    if not casterGuid then
        return nil, "Spell use needs a source unit"
    end

    Router:Inject("SPELL_GO_OTHER", casterGuid, spellId, targetGuid, 1, 0)
    return true
end

local function PrintHelp()
    Print("Usage:")
    Print("/azf mock on <unit> <spellId> [from <unit>]")
    Print("/azf mock from <unit> <spellId> [on <unit>]")
    Print("/azf mock cast <start|channel|ok|fail> <unit> <spellId> [on <unit>] [durationMs]")
    Print("/azf mock remove <unit> <spellId>")
end

local function HandleOn(tokens, count)
    if count ~= 3 and count ~= 5 then
        return nil, "usage: /azf on <unit> <spellId> [from <unit>]"
    end

    local targetGuid, targetErr = ResolveGuid(tokens[2])
    if targetErr then return nil, targetErr end

    local spellId, spellData, spellErr = ResolveTrackedSpell(tokens[3])
    if spellErr then return nil, spellErr end

    local sourceGuid = nil
    if count == 5 then
        if string.lower(tokens[4]) ~= "from" then
            return nil, "usage: /azf on <unit> <spellId> [from <unit>]"
        end
        local sourceErr
        sourceGuid, sourceErr = ResolveGuid(tokens[5])
        if sourceErr then return nil, sourceErr end
    end

    local appliedAura = false
    local usedSpell = false

    if spellData.trackAura then
        local ok, err = ApplyAura(spellId, spellData, sourceGuid, targetGuid)
        if not ok then
            return nil, err
        end
        appliedAura = true
    end

    if spellData.trackCd or spellData.resetsSpells then
        local useSourceGuid = sourceGuid
        local useTargetGuid = targetGuid

        if not useSourceGuid and spellData.targetMode == "self" then
            useSourceGuid = targetGuid
            useTargetGuid = nil
        end

        if useSourceGuid then
            local ok, err = UseSpell(spellId, spellData, useSourceGuid, useTargetGuid)
            if not ok then
                return nil, err
            end
            usedSpell = true
        end
    end

    if not appliedAura and not usedSpell then
        return nil, "Nothing to simulate for that spell with the supplied units"
    end

    Print("Applied " .. SpellLabel(spellId, spellData) .. " to the chosen unit.")
    return true
end

local function HandleFrom(tokens, count)
    if count ~= 3 and count ~= 5 then
        return nil, "usage: /azf from <unit> <spellId> [on <unit>]"
    end

    local sourceGuid, sourceErr = ResolveGuid(tokens[2])
    if sourceErr then return nil, sourceErr end

    local spellId, spellData, spellErr = ResolveTrackedSpell(tokens[3])
    if spellErr then return nil, spellErr end

    local targetGuid = nil
    if count == 5 then
        if string.lower(tokens[4]) ~= "on" then
            return nil, "usage: /azf from <unit> <spellId> [on <unit>]"
        end
        local targetErr
        targetGuid, targetErr = ResolveGuid(tokens[5])
        if targetErr then return nil, targetErr end
    end

    local usedSpell = false
    local appliedAura = false

    if spellData.trackCd or spellData.resetsSpells then
        local useTargetGuid = targetGuid
        if spellData.targetMode == "self" then
            useTargetGuid = nil
        end

        local ok, err = UseSpell(spellId, spellData, sourceGuid, useTargetGuid)
        if not ok then
            return nil, err
        end
        usedSpell = true
    end

    if spellData.trackAura then
        if spellData.targetMode == "self" or targetGuid then
            local ok, err = ApplyAura(spellId, spellData, sourceGuid, targetGuid)
            if not ok then
                return nil, err
            end
            appliedAura = true
        end
    end

    if not usedSpell and not appliedAura then
        return nil, "Spell needs an 'on <unit>' destination to apply its aura"
    end

    Print("Simulated " .. SpellLabel(spellId, spellData) .. " from the chosen unit.")
    return true
end

local function HandleCast(tokens, count)
    if count < 4 then
        return nil, "usage: /azf cast <start|channel|ok|fail> <unit> <spellId> [on <unit>] [durationMs]"
    end

    local mode = string.lower(tokens[2])
    local sourceGuid, sourceErr = ResolveGuid(tokens[3])
    if sourceErr then return nil, sourceErr end

    local spellId, spellData, spellErr = ResolveAnySpell(tokens[4])
    if spellErr then return nil, spellErr end

    local index = 5
    local targetToken, targetParseErr
    targetToken, targetParseErr, index = ParseOptionalTarget(tokens, index, count, "on")
    if targetParseErr then return nil, targetParseErr end

    local targetGuid = nil
    if targetToken then
        local targetErr
        targetGuid, targetErr = ResolveGuid(targetToken)
        if targetErr then return nil, targetErr end
    end

    if mode == "start" or mode == "channel" then
        local fallbackMs = mode == "channel" and DEFAULT_CHANNEL_MS or DEFAULT_CAST_MS
        local durationToken = nil
        if index <= count then
            durationToken = tokens[index]
            index = index + 1
        end

        local durationMs, durationErr = ParseDurationMs(durationToken, fallbackMs)
        if durationErr then return nil, durationErr end
        if index <= count then
            return nil, "usage: /azf cast <start|channel> <unit> <spellId> [on <unit>] [durationMs]"
        end

        local castTimeMs = mode == "channel" and 0 or durationMs
        local channelDurationMs = mode == "channel" and durationMs or 0
        local spellType = mode == "channel" and SPELLTYPE_CHANNEL or SPELLTYPE_NORMAL

        Router:Inject("SPELL_START_OTHER", sourceGuid, spellId, targetGuid, castTimeMs, channelDurationMs, spellType)
        Print("Started mock " .. mode .. " for " .. SpellLabel(spellId, spellData) .. ".")
        return true
    end

    if index <= count then
        return nil, "usage: /azf cast <ok|fail> <unit> <spellId> [on <unit>]"
    end

    if mode == "ok" then
        Router:Inject("SPELL_GO_OTHER", sourceGuid, spellId, targetGuid, 1, 0)
        Print("Completed mock cast for " .. SpellLabel(spellId, spellData) .. ".")
        return true
    end

    if mode == "fail" then
        Router:Inject("SPELL_FAILED_OTHER", sourceGuid, spellId)
        Print("Failed mock cast for " .. SpellLabel(spellId, spellData) .. ".")
        return true
    end

    return nil, "unknown cast mode '" .. tokens[2] .. "'"
end

local function HandleRemove(tokens, count)
    if count ~= 3 then
        return nil, "usage: /azf remove <unit> <spellId>"
    end

    local targetGuid, targetErr = ResolveGuid(tokens[2])
    if targetErr then return nil, targetErr end

    local spellId, spellData, spellErr = ResolveTrackedSpell(tokens[3])
    if spellErr then return nil, spellErr end
    if not spellData.trackAura then
        return nil, "Spell does not track an aura"
    end

    Router:Inject("BUFF_REMOVED_OTHER", targetGuid, spellId, 0, 0)
    Router:Inject("DEBUFF_REMOVED_OTHER", targetGuid, spellId, 0, 0)
    Print("Removed " .. SpellLabel(spellId, spellData) .. " from the chosen unit.")
    return true
end

local function Dispatch(tokens, count)
    if count == 0 then
        PrintHelp()
        return
    end

    local command = string.lower(tokens[1])

    local ok, err
    if command == "help" then
        PrintHelp()
        return
    elseif command == "on" then
        ok, err = HandleOn(tokens, count)
    elseif command == "from" then
        ok, err = HandleFrom(tokens, count)
    elseif command == "cast" then
        ok, err = HandleCast(tokens, count)
    elseif command == "remove" then
        ok, err = HandleRemove(tokens, count)
    else
        PrintHelp()
        return
    end

    if not ok then
        Print(err)
    end
end

function Mock:HandleSlash(message)
    local tokens, count = Tokenize(message or "")
    Dispatch(tokens, count)
end

function Mock:Init()
    if initialized then return end
    initialized = true

    Slash:Register("mock", function(message)
        Mock:HandleSlash(message)
    end)
end
