-- ==========================================================================
-- render/IconFactory.lua
-- ==========================================================================
-- Purpose:  Centralized icon slot builder. Produces a complete icon with
--           cropped texture, 8-piece beveled border, cooldown sweep model,
--           and pre-positioned timer FontString. Reusable across all strip
--           renderers (target, nameplate, future arena/focus).
-- Owns:     IconFactory:Create and preset config tables.
-- Does NOT: Fill icon data, manage animation registries, or own layout.
-- Used by:  render/TargetRenderer.lua, render/NameplateRenderer.lua.
-- Calls:    AzF.Border (border creation).
-- ==========================================================================

local IconFactory = AzF.IconFactory
local Border      = AzF.Border
local max         = math.max

-- -------------------------------------------------------------------------
-- Preset configurations
-- -------------------------------------------------------------------------

IconFactory.NAMEPLATE_CONFIG = {
    width         = 20,
    height        = 16,
    iconCropL     = 0.1,
    iconCropR     = 0.9,
    iconCropT     = 0.25,
    iconCropB     = 0.75,
    borderSize    = 14,
    borderPadding = 1.2,
    sweepOffsetY  = -1,
    timerFontSize = 10,
    timerOffsetY  = -2,
}

IconFactory.TARGET_CONFIG = {
    width         = 30,
    height        = 24,
    iconCropL     = 0.1,
    iconCropR     = 0.9,
    iconCropT     = 0.25,
    iconCropB     = 0.75,
    borderSize    = 21,
    borderPadding = 1.8,
    sweepOffsetY  = 0,
    timerFontSize = 12,
    timerOffsetY  = -3,
}

-- -------------------------------------------------------------------------
-- Icon creation
-- -------------------------------------------------------------------------

local function GetSweepScale(cfg)
    return max(cfg.width, cfg.height) / 36
end

-- Create a single icon slot with the enemyFrames-style layering.
--
-- Layering order (bottom to top):
--   1. base frame (width x height)
--   2. icon texture (ARTWORK on base, cropped via SetTexCoord)
--   3. sweep host frame (SetAllPoints on base)
--      -> inner model anchor (optionally nudged, but still icon-sized)
--      -> Model (CooldownFrameTemplate, scaled to sweepScale)
--   4. overlay frame (SetAllPoints on base)
--      -> 8-piece border
--      -> timer FontString (OVERLAY, anchored below icon)
--
-- @param parent  The parent frame to attach the icon to.
-- @param cfg     A config table (use NAMEPLATE_CONFIG or TARGET_CONFIG).
-- @param index   Icon index within the strip (for frame level spacing).
-- @return table  { frame, texture, model, border, overlay }
--                overlay is the timer host frame for TimerText compat.
function IconFactory:Create(parent, cfg, index)
    local baseLevel = parent:GetFrameLevel() + 1 + (index - 1) * 3
    local sweepSize = max(cfg.width, cfg.height)

    -- 1. Base frame
    local base = CreateFrame("Frame", nil, parent)
    base:SetWidth(cfg.width)
    base:SetHeight(cfg.height)
    base:SetFrameLevel(baseLevel)

    -- 2. Icon texture (cropped)
    local tex = base:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(base)
    tex:SetTexCoord(cfg.iconCropL, cfg.iconCropR, cfg.iconCropT, cfg.iconCropB)

    -- 3. Sweep host + inner anchor + cooldown model
    local sweepHost = CreateFrame("Frame", nil, base)
    sweepHost:SetAllPoints(base)
    sweepHost:SetFrameLevel(baseLevel + 1)

    local modelAnchor = CreateFrame("Frame", nil, sweepHost)
    modelAnchor:SetWidth(sweepSize)
    modelAnchor:SetHeight(sweepSize)
    modelAnchor:SetPoint("CENTER", sweepHost, "CENTER", 0, cfg.sweepOffsetY or 0)
    modelAnchor:SetFrameLevel(baseLevel + 1)

    local model = CreateFrame("Model", nil, modelAnchor, "CooldownFrameTemplate")
    model:SetAllPoints(modelAnchor)
    model:SetScale(GetSweepScale(cfg))

    -- 4. Overlay frame with border and timer
    local overlay = CreateFrame("Frame", nil, base)
    overlay:SetAllPoints(base)
    overlay:SetFrameLevel(baseLevel + 2)

    local border = Border:Create(overlay, cfg.borderSize)
    border:SetPadding(cfg.borderPadding)

    -- 5. Timer FontString on the border frame so it stays above the border art.
    --    TimerText still uses the overlay host; we just pre-create the FontString here.
    local fs = border:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, cfg.timerFontSize, "OUTLINE")
    fs:SetTextColor(0.9, 0.9, 0.2, 1)
    fs:SetPoint("CENTER", base, "BOTTOM", 0, cfg.timerOffsetY)
    overlay.azfTimerFS = fs

    return {
        frame   = base,
        texture = tex,
        model   = model,
        border  = border,
        overlay = overlay,
    }
end
