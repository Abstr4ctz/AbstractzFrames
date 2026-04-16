-- ==========================================================================
-- AbstractzFrames.lua
-- ==========================================================================
-- Purpose:  Entry-point sequencer. Runs once on PLAYER_LOGIN to verify
--           dependencies, set CVars, initialize data, and report status.
-- Owns:     Startup sequence only. No feature logic lives here.
-- ==========================================================================

local loginFrame = CreateFrame("Frame", "AzFLoginFrame", UIParent)
loginFrame:RegisterEvent("PLAYER_LOGIN")

loginFrame:SetScript("OnEvent", function()
    loginFrame:UnregisterEvent("PLAYER_LOGIN")

    -- ---------------------------------------------------------------
    -- 1. Verify required dependencies
    -- ---------------------------------------------------------------
    -- nampower and UnitXP_SP3 are client mods that inject globals, not
    -- standard addons, so we check for the functions they provide.
    local missing = {}

    if type(GetNampowerVersion) ~= "function" then
        table.insert(missing, "nampower")
    end

    if type(UnitXP) ~= "function" then
        table.insert(missing, "UnitXP_SP3")
    end

    if table.getn(missing) > 0 then
        local list = table.concat(missing, ", ")
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff3333[AbstractzFrames] Missing required mods: " .. list .. ". Addon will not load.|r"
        )
        return
    end

    -- ---------------------------------------------------------------
    -- 2. Enable nampower CVars for spell/aura event support
    -- ---------------------------------------------------------------
    SetCVar("NP_EnableSpellGoEvents", "1")
    SetCVar("NP_EnableSpellStartEvents", "1")
    SetCVar("NP_EnableAuraCastEvents", "1")

    -- ---------------------------------------------------------------
    -- 3. Initialize saved variables
    -- ---------------------------------------------------------------
    AzF.DB:Init()

    -- ---------------------------------------------------------------
    -- 4. Capture player identity for class-specific and future GUID logic
    -- ---------------------------------------------------------------
    local playerClass = AzF.Player:Init()

    -- ---------------------------------------------------------------
    -- 5. Initialize spell database from DBC data
    -- ---------------------------------------------------------------
    AzF.SpellDB:Init(playerClass)

    -- ---------------------------------------------------------------
    -- 6. Initialize feature handlers
    -- ---------------------------------------------------------------
    AzF.Cooldowns:Init()
    AzF.Auras:Init()
    AzF.Casts:Init()

    -- ---------------------------------------------------------------
    -- 7. Initialize bindings and renderers
    -- ---------------------------------------------------------------
    AzF.CastBar:Init()
    AzF.Target:Init()
    AzF.TargetRenderer:Init()
    AzF.ReverseSweep:Init()
    AzF.TimerText:Init()
    AzF.TargetPortraitRenderer:Init()
    AzF.Nameplates:Init()
    AzF.NameplateRenderer:Init()
    AzF.Slash:Init()
    AzF.Mock:Init()

    -- ---------------------------------------------------------------
    -- 8. Zone-change wipe
    -- ---------------------------------------------------------------
    -- PLAYER_ENTERING_WORLD fires on zone changes and on initial login
    -- (after PLAYER_LOGIN). Wipe ExpiryIndex first (it references entry
    -- objects in SpellState), then ActiveFrames, then SpellState last.
    AzF.EventBus:Subscribe("PLAYER_ENTERING_WORLD", function()
        AzF.Auras:WipeMaxStacks()
        AzF.Casts:Wipe()
        AzF.ExpiryIndex:Wipe()
        AzF.ActiveFrames:Wipe()
        AzF.SpellState:Wipe()
        AzF.TimerText:StopAll()
        AzF.CastBar:HideAll()
        AzF.TargetRenderer:Hide()
        AzF.TargetPortraitRenderer:Hide()
        AzF.NameplateRenderer:HideAll()
        AzF.Nameplates:Wipe()

        -- Enable or disable combat tracking based on zone.
        -- Forbidden zones (raids, dungeons) have no PvP activity.
        if AzF.ZoneData:IsForbiddenZone() then
            AzF.Router:Disable()
        else
            AzF.Router:Enable()
        end
    end)

    -- ---------------------------------------------------------------
    -- 9. Done
    -- ---------------------------------------------------------------
    DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66[AbstractzFrames] Loaded.|r")
end)
