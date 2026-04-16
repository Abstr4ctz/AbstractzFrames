-- ==========================================================================
-- data/SpellDB.lua
-- ==========================================================================
-- Purpose:  Expands authored spell templates into per-ID entries, then
--           populates DBC-derived fields (name, icon, rank, duration,
--           cooldown, texture, dispelType, school).
-- Owns:     The Init method on AzF.SpellDB. Template data is authored in
--           SpellDB_Entries.lua.
-- Does NOT: Subscribe to events, access runtime state, or create frames.
-- Used by:  AbstractzFrames.lua calls SpellDB:Init(playerClass) at PLAYER_LOGIN.
-- Calls:    GetSpellRecField, GetSpellDuration, GetSpellIconTexture (guarded).
-- ==========================================================================

local SpellDB = AzF.SpellDB

-- Keys excluded when copying template fields into a per-ID entry.
local TEMPLATE_SKIP = { ids = true, classPriority = true, resetsSpells = true }

-- Expand AzF.SpellTemplates into flat SpellDB[numericId] = entry tables.
-- Resolves per-rank overrides, resetsSpells template references, and
-- inline classPriority.
local function expandTemplates(playerClass)
    local templates = AzF.SpellTemplates
    if not templates then return end

    -- First pass: expand each template into per-ID entries.
    for tplKey, tpl in pairs(templates) do
        if not tpl.ids then break end

        for _, idEntry in ipairs(tpl.ids) do
            local id = type(idEntry) == "number" and idEntry or idEntry[1]

            -- Shallow-copy base fields.
            local entry = {}
            for k, v in pairs(tpl) do
                if not TEMPLATE_SKIP[k] then
                    entry[k] = v
                end
            end

            -- Apply per-rank overrides.
            if type(idEntry) == "table" then
                for k, v in pairs(idEntry) do
                    if k ~= 1 then
                        entry[k] = v
                    end
                end
            end

            -- Resolve inline classPriority.
            if tpl.classPriority and playerClass then
                local prio = tpl.classPriority[playerClass]
                if prio then
                    entry.classPriority = prio
                end
            end

            SpellDB[id] = entry
        end
    end

    -- Second pass: resolve resetsSpells template-key strings to numeric ID sets.
    for tplKey, tpl in pairs(templates) do
        if tpl.resetsSpells then
            local resetSet = {}
            for _, refKey in ipairs(tpl.resetsSpells) do
                local refTpl = templates[refKey]
                if refTpl and refTpl.ids then
                    for _, idEntry in ipairs(refTpl.ids) do
                        local id = type(idEntry) == "number" and idEntry or idEntry[1]
                        resetSet[id] = true
                    end
                end
            end
            -- Write the resolved set onto every entry expanded from this template.
            for _, idEntry in ipairs(tpl.ids) do
                local id = type(idEntry) == "number" and idEntry or idEntry[1]
                if SpellDB[id] then
                    SpellDB[id].resetsSpells = resetSet
                end
            end
        end
    end
end

-- Enrich every entry with data from the client's DBC tables.
-- Each DBC API call is guarded because these are nampower-provided functions
-- that may not exist on all clients.
function SpellDB:Init(playerClass)
    expandTemplates(playerClass)

    local hasRecField   = type(GetSpellRecField) == "function"
    local hasDuration   = type(GetSpellDuration) == "function"
    local hasIconTex    = type(GetSpellIconTexture) == "function"

    for spellId, entry in pairs(self) do
        if type(entry) == "table" then
            -- Always populate from DBC when the API is available.
            if hasRecField then
                entry.name       = GetSpellRecField(spellId, "name")
                entry.icon       = GetSpellRecField(spellId, "spellIconID")
                entry.rankStr    = GetSpellRecField(spellId, "rank")
                entry.dispelType = GetSpellRecField(spellId, "dispel")
                entry.school     = GetSpellRecField(spellId, "school")
            end

            -- Auto-populate duration only if the author did not set one.
            if (not entry.duration or entry.duration == 0) and hasDuration then
                local durationMs = GetSpellDuration(spellId, 1)
                if durationMs and durationMs > 0 then
                    entry.duration = durationMs / 1000
                end
            end

            -- Auto-populate cooldown only if the author did not set one.
            if (not entry.cooldown or entry.cooldown == 0) and hasRecField then
                local recoveryMs = GetSpellRecField(spellId, "recoveryTime")
                if recoveryMs and recoveryMs > 0 then
                    entry.cooldown = recoveryMs / 1000
                end
            end

            -- Resolve the icon texture path from the icon ID.
            if entry.icon and hasIconTex then
                entry.iconTexture = GetSpellIconTexture(entry.icon)
            end
        end
    end
end
