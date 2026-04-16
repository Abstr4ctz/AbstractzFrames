-- ==========================================================================
-- data/DB.lua
-- ==========================================================================
-- Purpose:  Owns SavedVariables schema and default-merge logic.
-- Owns:     AzF.DB (self-declared here, not in Namespace.lua, because Init
--           replaces the table reference with the live SavedVariables table).
-- Does NOT: Contain feature-specific settings for systems that do not exist.
-- Used by:  AbstractzFrames.lua (entry-point) calls Init on login.
-- Calls:    Nothing external. Pure data logic.
-- ==========================================================================

AzF.DB = {}

-- Default saved-variables structure. Keep minimal -- only add keys when a
-- real system needs them.
local DEFAULTS = {}

-- -------------------------------------------------------------------------
-- ApplyDefaults: recursively merge missing keys from defaults into target.
-- Existing keys in target are never overwritten.
-- -------------------------------------------------------------------------
local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                ApplyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

-- -------------------------------------------------------------------------
-- Init: ensure SavedVariables exist, merge defaults, and swap AzF.DB to
-- point at the live AzFDB table so all future reads/writes go there.
-- -------------------------------------------------------------------------
function AzF.DB:Init()
    -- Create the global SavedVariables table if this is a first run
    -- or if it was corrupted to a non-table value.
    if type(AzFDB) ~= "table" then
        AzFDB = {}
    end

    ApplyDefaults(AzFDB, DEFAULTS)

    -- Replace AzF.DB with the live SavedVariables reference.
    AzF.DB = AzFDB
end
