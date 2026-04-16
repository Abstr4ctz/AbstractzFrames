-- ==========================================================================
-- render/TargetPortraitRenderer.lua
-- ==========================================================================
-- Purpose:  Renders a single portrait badge showing the highest-priority
--           active aura on the player's current target.
-- Owns:     The portrait overlay frame and show/hide logic.
-- Does NOT: Subscribe to events, write spell state, sort, or own gameplay data.
-- Used by:  VisualSync dispatches pre-sorted aura display list here.
-- Calls:    AzF.ReverseSweep (sweep).
--
-- Layer structure (based on TargetFrame debug data):
--   TargetPortrait is a BORDER texture on TargetFrame (level 1).
--   TargetFrameTextureFrame is the gold border at level 2.
--
--   Icon:  ARTWORK texture on TargetFrame — above BORDER (portrait),
--          below gold border (level 2). Sized smaller than the portrait
--          circle so the gold border hides the square corners.
--   Sweep: CooldownFrameTemplate on a level 0 frame — 3D model renders
--          above 2D textures regardless of frame level. Matches icon size.
--   Ring:  OVERLAY texture on TargetFrame — thin annular ring covering
--          the gap between the undersized icon edges and the gold border's
--          circular opening. Tinted by dispel type via SetVertexColor.
-- ==========================================================================

local TargetPortraitRenderer = AzF.TargetPortraitRenderer
local ReverseSweep          = AzF.ReverseSweep
local TimerText             = AzF.TimerText

-- ======================= TUNING KNOBS ==========================
-- Adjust these to align the aura badge with the gold border's
-- circular opening. Re-run generate_portrait_ring.py after changing
-- ring geometry.
--
-- ICON_SIZE:     Square display size of the spell icon (px).
--                Smaller → corners more hidden by gold border,
--                but wider gap for the ring to fill.
-- ICON_CROP:     Texcoord inset (0-0.5). Crops the icon texture inward,
--                cutting off the dark border most spell icons have.
--                0.12 matches enemyFrames. 0 = no crop.
-- OPTICAL_OFFSET_X: Horizontal nudge from portrait center (+ = right).
-- OPTICAL_OFFSET_Y: Vertical nudge from portrait center (+ = up).
--                   This is the shared optical center for icon, sweep,
--                   and ring. Keep X at 0 unless testing proves otherwise.
-- RING_SIZE:     Square display size of the ring texture (px).
--                Should match or slightly underfill the portrait opening.
--
-- Ring inner/outer radius lives in generate_portrait_ring.py.
-- Display mapping: display_radius = texture_radius * RING_SIZE / 128
-- ================================================================
local ICON_SIZE      = 50
local ICON_CROP      = 0.12
local OPTICAL_OFFSET_X = 0
local OPTICAL_OFFSET_Y = -1.75
local RING_SIZE      = 64

-- Dispel-type ring colors. Keys are DBC dispel enum values.
local DISPEL_COLORS = {
    [1] = { 0.2, 0.6, 1.0 },   -- Magic (blue)
    [2] = { 0.6, 0.0, 1.0 },   -- Curse (purple)
    [3] = { 0.6, 0.4, 0.0 },   -- Disease (brown)
    [4] = { 0.0, 0.6, 0.0 },   -- Poison (green)
}
local DEFAULT_RING_COLOR = { 0.8, 0.0, 0.0 }

-- Module state
local disabled      = false
local badgeAnchor   = nil
local container     = nil
local iconTex       = nil
local sweepModel    = nil
local ringTex       = nil
local timerOverlay  = nil

function TargetPortraitRenderer:Init()
    if container then return end

    -- Guard: silently disable if TargetPortrait does not exist
    -- (custom unit frame addons may remove it).
    if not TargetPortrait then
        disabled = true
        return
    end

    -- Shared optical center for icon, sweep, and ring. This gives us one
    -- alignment target instead of separate icon/ring nudges.
    badgeAnchor = CreateFrame("Frame", "AzFTargetPortraitBadgeAnchor", TargetFrame)
    badgeAnchor:SetWidth(1)
    badgeAnchor:SetHeight(1)
    badgeAnchor:SetPoint("CENTER", TargetPortrait, "CENTER", OPTICAL_OFFSET_X, OPTICAL_OFFSET_Y)
    badgeAnchor:SetFrameLevel(0)

    -- Sweep container at level 0, sized to match the icon and anchored to
    -- the shared optical center. container:Hide() hides only the sweep.
    container = CreateFrame("Frame", "AzFTargetPortraitBadge", TargetFrame)
    container:SetWidth(ICON_SIZE)
    container:SetHeight(ICON_SIZE)
    container:SetPoint("CENTER", badgeAnchor, "CENTER", 0, 0)
    container:SetFrameLevel(0)

    -- Icon: ARTWORK texture on TargetFrame.
    -- Sized smaller than the portrait circle so the gold border (level 2)
    -- hides the square corners. The gap between icon edge and gold border
    -- opening is covered by the ring below.
    iconTex = TargetFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetWidth(ICON_SIZE)
    iconTex:SetHeight(ICON_SIZE)
    iconTex:SetPoint("CENTER", badgeAnchor, "CENTER", 0, 0)
    if ICON_CROP > 0 then
        iconTex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end
    iconTex:Hide()

    -- Sweep: CooldownFrameTemplate on the level 0 container.
    -- 3D models render above 2D textures regardless of frame level.
    sweepModel = CreateFrame("Model", nil, container, "CooldownFrameTemplate")
    sweepModel:SetAllPoints(container)
    sweepModel:SetScale(ICON_SIZE / 36)
    sweepModel:Hide()

    -- Timer text overlay: sits above the sweep model in the frame stack.
    -- The FontString is created lazily by TimerText on first Start() call.
    timerOverlay = CreateFrame("Frame", nil, TargetFrame)
    timerOverlay:SetWidth(ICON_SIZE)
    timerOverlay:SetHeight(ICON_SIZE)
    timerOverlay:SetPoint("CENTER", badgeAnchor, "CENTER", 0, 0)
    timerOverlay:SetFrameLevel(container:GetFrameLevel() + 2)

    -- Ring: OVERLAY texture on TargetFrame.
    -- Thin annulus covering the gap between the icon edges and the gold
    -- border's circular opening. Transparent center shows the icon;
    -- opaque ring hides the portrait peeking through at the edges.
    -- Tinted by dispel type. Gold border covers the ring's square edges.
    ringTex = TargetFrame:CreateTexture(nil, "OVERLAY")
    ringTex:SetWidth(RING_SIZE)
    ringTex:SetHeight(RING_SIZE)
    ringTex:SetPoint("CENTER", badgeAnchor, "CENTER", 0, 0)
    ringTex:SetTexture([[Interface\AddOns\AbstractzFrames\assets\portraitRing.tga]])
    ringTex:SetVertexColor(DEFAULT_RING_COLOR[1], DEFAULT_RING_COLOR[2], DEFAULT_RING_COLOR[3])
    ringTex:Hide()

    container:Hide()
end

function TargetPortraitRenderer:Refresh(auraBuf, auraCount)
    if disabled then return end

    if auraCount == 0 then
        self:Hide()
        return
    end

    -- The display list is sorted by priority. The winner is always [1].
    local winner = auraBuf[1]

    iconTex:SetTexture(winner.iconTexture)
    iconTex:Show()

    -- Tint ring by dispel type.
    local color = DISPEL_COLORS[winner.dispelType] or DEFAULT_RING_COLOR
    ringTex:SetVertexColor(color[1], color[2], color[3])
    ringTex:Show()

    -- Reverse sweep: empty-to-filled (dark region grows as aura expires).
    if winner.startedAt and winner.expiresAt and winner.expiresAt > winner.startedAt then
        ReverseSweep:Start(sweepModel, winner.startedAt, winner.expiresAt - winner.startedAt)
        TimerText:Start(timerOverlay, winner.expiresAt)
    else
        ReverseSweep:Stop(sweepModel)
        TimerText:Stop(timerOverlay)
    end

    container:Show()
end

function TargetPortraitRenderer:Hide()
    if disabled then return end

    if container then
        iconTex:Hide()
        ringTex:Hide()
        ReverseSweep:Stop(sweepModel)
        TimerText:Stop(timerOverlay)
        container:Hide()
    end
end
