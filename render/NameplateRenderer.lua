-- ==========================================================================
-- render/NameplateRenderer.lua
-- ==========================================================================
-- Purpose:  Renders castbar, aura icons, and cooldown icons on nameplate
--           overlay frames.
-- Owns:     Per-plate overlay creation, castbar widgets, icon subframes,
--           and Refresh/Hide logic.
-- Does NOT: Subscribe to events, write spell state, sort, or know about GUIDs.
-- Used by:  VisualSync dispatches pre-sorted display lists here with (plate, state).
-- Calls:    AzF.IconFactory (icon creation), AzF.IconFill (slot fill),
--           AzF.CastBar, CooldownFrame_SetTimer.
-- ==========================================================================

local NameplateRenderer = AzF.NameplateRenderer
local CastBar           = AzF.CastBar
local IconFill          = AzF.IconFill
local IconFactory       = AzF.IconFactory

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local CFG = IconFactory.NAMEPLATE_CONFIG
local NP_ICON_WIDTH       = CFG.width
local NP_ICON_HEIGHT      = CFG.height
local NP_AURA_COUNT       = 3
local NP_CD_COUNT         = 2
local NP_ICON_SPACING     = 2
local NP_GROUP_GAP        = 4
local NP_CASTBAR_HEIGHT   = 8
local NP_CASTBAR_OFFSET_Y = -3
local NP_ICONS_OFFSET_Y   = 2

-- Set of all plates that have received an overlay (for HideAll).
local overlayPlates = {}

-- ---------------------------------------------------------------------------
-- Overlay creation (lazy, called on first Refresh for a plate)
-- ---------------------------------------------------------------------------

local function CreateOverlay(plate)
    local healthBar = plate:GetChildren()

    local overlay = CreateFrame("Frame", nil, plate)
    overlay:SetAllPoints(plate)
    overlay:SetFrameLevel(plate:GetFrameLevel() + 1)
    overlay.healthBar = healthBar

    -- ---- Icon strip (above health bar) ----
    local stripWidth = NP_AURA_COUNT * NP_ICON_WIDTH
                     + (NP_AURA_COUNT - 1) * NP_ICON_SPACING
                     + NP_GROUP_GAP
                     + NP_CD_COUNT * NP_ICON_WIDTH
                     + (NP_CD_COUNT - 1) * NP_ICON_SPACING
    local iconStrip = CreateFrame("Frame", nil, overlay)
    iconStrip:SetWidth(stripWidth)
    iconStrip:SetHeight(NP_ICON_HEIGHT)
    iconStrip:SetPoint("BOTTOM", healthBar, "TOP", 0, NP_ICONS_OFFSET_Y)
    iconStrip:SetFrameLevel(overlay:GetFrameLevel() + 1)

    local auraIcons = {}
    local xOffset = 0
    for i = 1, NP_AURA_COUNT do
        local icon = IconFactory:Create(iconStrip, CFG, i)
        icon.frame:SetPoint("TOPLEFT", iconStrip, "TOPLEFT", xOffset, 0)
        auraIcons[i] = icon
        xOffset = xOffset + NP_ICON_WIDTH + NP_ICON_SPACING
    end

    xOffset = xOffset - NP_ICON_SPACING + NP_GROUP_GAP

    local cdIcons = {}
    for i = 1, NP_CD_COUNT do
        local icon = IconFactory:Create(iconStrip, CFG, NP_AURA_COUNT + i)
        icon.frame:SetPoint("TOPLEFT", iconStrip, "TOPLEFT", xOffset, 0)
        cdIcons[i] = icon
        xOffset = xOffset + NP_ICON_WIDTH + NP_ICON_SPACING
    end

    -- ---- Castbar (below health bar) ----
    local castBar = CastBar:Create(overlay, healthBar:GetWidth(), NP_CASTBAR_HEIGHT)
    castBar:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", 0, NP_CASTBAR_OFFSET_Y)
    castBar:SetFrameLevel(overlay:GetFrameLevel() + 1)

    overlay.auraIcons = auraIcons
    overlay.cdIcons   = cdIcons
    overlay.iconStrip = iconStrip
    overlay.castBar   = castBar

    iconStrip:Hide()
    castBar:Hide()

    overlayPlates[plate] = true
    return overlay
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function NameplateRenderer:Refresh(plate, state, auraBuf, auraCount, cdBuf, cdCount)
    local overlay = plate.azfOverlay
    if not overlay then
        overlay = CreateOverlay(plate)
        plate.azfOverlay = overlay
    end

    local now = GetTime()
    CastBar:Refresh(overlay.castBar, state and state.cast, now)

    IconFill:FillAuras(overlay.auraIcons, auraBuf, auraCount)
    IconFill:FillCooldowns(overlay.cdIcons, cdBuf, cdCount)

    if auraCount > 0 or cdCount > 0 then
        overlay.iconStrip:Show()
    else
        overlay.iconStrip:Hide()
    end
end

function NameplateRenderer:HideOverlay(plate)
    local overlay = plate.azfOverlay
    if not overlay then return end
    CastBar:Hide(overlay.castBar)
    IconFill:StopAuras(overlay.auraIcons, NP_AURA_COUNT)
    IconFill:StopTimers(overlay.cdIcons, NP_CD_COUNT)
    overlay.iconStrip:Hide()
end

function NameplateRenderer:HideAll()
    for plate in pairs(overlayPlates) do
        local overlay = plate.azfOverlay
        if overlay then
            CastBar:Hide(overlay.castBar)
            IconFill:StopAuras(overlay.auraIcons, NP_AURA_COUNT)
            IconFill:StopTimers(overlay.cdIcons, NP_CD_COUNT)
            overlay.iconStrip:Hide()
        end
    end
end

function NameplateRenderer:Init()
end
