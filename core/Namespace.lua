-- ==========================================================================
-- core/Namespace.lua
-- ==========================================================================
-- Purpose:  Declares the single global addon table (AzF) and near-term
--           module sub-tables.
-- Owns:     The AzF global and its top-level structure.
-- Does NOT: Initialize modules, store data, or run any logic.
-- Used by:  Every other addon file reads from or writes into AzF.
-- Calls:    Nothing. This file only declares tables.
-- ==========================================================================

AzF = {}

-- EventBus is declared here because its table is stable (never replaced).
AzF.EventBus = {}
AzF.Slash = {}

-- Router is declared here because, like EventBus, its table identity is
-- stable (never replaced). Handlers hold a reference to this table.
AzF.Router = {}
AzF.Player = {}

-- SpellDB is declared here. SpellDB_Entries.lua populates it at file scope.
-- SpellDB:Init(playerClass) enriches entries at PLAYER_LOGIN.
AzF.SpellDB = {}

-- ZoneData is declared here. Pure zone-classification data (no Init).
AzF.ZoneData = {}

AzF.SpellState = {}

AzF.Cooldowns = {}

AzF.DR = {}

AzF.Auras = {}

AzF.ExpiryIndex = {}
AzF.ActiveFrames = {}
AzF.Driver = {}
AzF.Target = {}
AzF.TargetRenderer = {}
AzF.TargetPortraitRenderer = {}
AzF.VisualSync = {}
AzF.CastBar = {}
AzF.ReverseSweep = {}
AzF.TimerText    = {}
AzF.IconFill     = {}
AzF.DisplayList = {}
AzF.Border      = {}
AzF.IconFactory = {}

AzF.Casts = {}
AzF.Nameplates = {}
AzF.NameplateRenderer = {}
AzF.Mock = {}

-- NOTE: AzF.DB is NOT declared here. data/DB.lua self-declares it because
-- Init() replaces the table reference with the live SavedVariables table.
