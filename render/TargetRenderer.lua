-- ==========================================================================
-- render/TargetRenderer.lua
-- ==========================================================================
-- Purpose:  Renders tracked auras and cooldowns on the player's target as
--           icon frames with cooldown sweep animations and beveled borders.
-- Owns:     The target overlay frame, icon sub-frames, and Refresh/Hide logic.
-- Does NOT: Subscribe to combat events, write spell state, sort, or own gameplay data.
-- Used by:  VisualSync dispatches pre-sorted display lists here.
-- Calls:    AzF.IconFactory (icon creation), AzF.IconFill (slot fill).
-- ==========================================================================

local TargetRenderer = AzF.TargetRenderer
local IconFactory    = AzF.IconFactory
local IconFill       = AzF.IconFill

local AURA_ICON_COUNT     = 5
local COOLDOWN_ICON_COUNT = 4

local CFG = IconFactory.TARGET_CONFIG
local ICON_WIDTH   = CFG.width
local ICON_HEIGHT  = CFG.height
local ICON_SPACING = 3
local GROUP_GAP    = 8
local FRAME_PADDING = 4

local AURA_GROUP_WIDTH = AURA_ICON_COUNT * ICON_WIDTH + (AURA_ICON_COUNT - 1) * ICON_SPACING
local COOLDOWN_GROUP_WIDTH = COOLDOWN_ICON_COUNT * ICON_WIDTH + (COOLDOWN_ICON_COUNT - 1) * ICON_SPACING
local CONTAINER_WIDTH = FRAME_PADDING + AURA_GROUP_WIDTH + GROUP_GAP + COOLDOWN_GROUP_WIDTH + FRAME_PADDING
local CONTAINER_HEIGHT = ICON_HEIGHT + FRAME_PADDING * 2

-- Icon sub-frame arrays, populated by Init.
local auraIcons = {}
local cdIcons = {}

-- The container frame, created by Init.
local container = nil

function TargetRenderer:Init()
    if container then return end

    container = CreateFrame("Frame", "AzFTargetRenderer", UIParent)
    container:SetWidth(CONTAINER_WIDTH)
    container:SetHeight(CONTAINER_HEIGHT)
    container:SetPoint("TOP", TargetFrame, "BOTTOM", 0, -2)
    container:Hide()

    -- Create aura icons (left side)
    local xOffset = FRAME_PADDING
    for i = 1, AURA_ICON_COUNT do
        local icon = IconFactory:Create(container, CFG, i)
        icon.frame:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset, -FRAME_PADDING)
        auraIcons[i] = icon
        xOffset = xOffset + ICON_WIDTH + ICON_SPACING
    end

    -- Gap between groups (remove the last ICON_SPACING, add GROUP_GAP)
    xOffset = xOffset - ICON_SPACING + GROUP_GAP

    -- Create cooldown icons (right side)
    for i = 1, COOLDOWN_ICON_COUNT do
        local icon = IconFactory:Create(container, CFG, AURA_ICON_COUNT + i)
        icon.frame:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset, -FRAME_PADDING)
        cdIcons[i] = icon
        xOffset = xOffset + ICON_WIDTH + ICON_SPACING
    end
end

function TargetRenderer:Refresh(auraBuf, auraCount, cdBuf, cdCount)
    if auraCount == 0 and cdCount == 0 then
        self:Hide()
        return
    end

    IconFill:FillAuras(auraIcons, auraBuf, auraCount)
    IconFill:FillCooldowns(cdIcons, cdBuf, cdCount)

    container:Show()
end

function TargetRenderer:Hide()
    if container then
        IconFill:StopAuras(auraIcons, AURA_ICON_COUNT)
        IconFill:StopTimers(cdIcons, COOLDOWN_ICON_COUNT)
        container:Hide()
    end
end
