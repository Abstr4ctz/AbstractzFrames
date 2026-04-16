-- ==========================================================================
-- data/ZoneData.lua
-- ==========================================================================
-- Purpose:  Pure zone-classification data. Classifies zones into forbidden
--           (raids/dungeons), arena, and battleground categories.
-- Owns:     Three lookup tables (forbiddenZones, arenaZones, bgZones) and
--           three query functions (IsForbiddenZone, IsArena, IsBattleground).
-- Does NOT: Subscribe to events, create frames, or contain Init logic.
-- Used by:  Entry point zone-change handler, future arena/BG modules.
-- Calls:    GetRealZoneText() (WoW API).
-- ==========================================================================

local ZoneData = AzF.ZoneData

-- All zone strings must match GetRealZoneText() returns exactly (case-sensitive).
-- Turtle WoW may have custom instances not listed here. Verify in-game and add
-- as needed using: /script DEFAULT_CHAT_FRAME:AddMessage(GetRealZoneText())

-- Raids and dungeons where the addon should be completely disabled.
-- No PvP activity occurs in these zones.
local forbiddenZones = {
    -- Raids
    ["Molten Core"]            = true,
    ["Blackwing Lair"]         = true,
    ["Zul'Gurub"]              = true,
    ["Ruins of Ahn'Qiraj"]    = true,
    ["Temple of Ahn'Qiraj"]   = true,
    ["Naxxramas"]              = true,
    ["Onyxia's Lair"]          = true,
    -- Dungeons
    ["Ragefire Chasm"]         = true,
    ["The Deadmines"]          = true,
    ["Wailing Caverns"]        = true,
    ["The Stockade"]           = true,
    ["Shadowfang Keep"]        = true,
    ["Blackfathom Deeps"]      = true,
    ["Gnomeregan"]             = true,
    ["Scarlet Monastery"]      = true,
    ["Razorfen Kraul"]         = true,
    ["Razorfen Downs"]         = true,
    ["Uldaman"]                = true,
    ["Zul'Farrak"]             = true,
    ["Maraudon"]               = true,
    ["Sunken Temple"]          = true,
    ["Blackrock Depths"]       = true,
    ["Blackrock Spire"]        = true,
    ["Dire Maul"]              = true,
    ["Stratholme"]             = true,
    ["Scholomance"]            = true,
}

-- Turtle WoW arena zones. These names are PROVISIONAL and UNVERIFIED.
-- Must be tested in-game before arena features are built.
local arenaZones = {
    ["Ruins of Lordaeron"]     = true,
    ["Blade's Edge Arena"]     = true,
}

-- Standard Vanilla battlegrounds.
local bgZones = {
    ["Warsong Gulch"]          = true,
    ["Arathi Basin"]           = true,
    ["Alterac Valley"]         = true,
}

-- =========================================================================
-- Query Functions
-- =========================================================================

-- Returns true if the player is in a raid or dungeon where the addon
-- should be completely disabled.
function ZoneData:IsForbiddenZone()
    return forbiddenZones[GetRealZoneText()] == true
end

-- Returns true if the player is in an arena instance.
function ZoneData:IsArena()
    return arenaZones[GetRealZoneText()] == true
end

-- Returns true if the player is in a battleground.
function ZoneData:IsBattleground()
    return bgZones[GetRealZoneText()] == true
end
