-- ==========================================================================
-- render/IconFill.lua
-- ==========================================================================
-- Purpose:  Shared icon-slot fill and cleanup for aura and cooldown strips.
-- Owns:     FillAuras, FillCooldowns, StopAuras, StopTimers logic,
--           and border color application per dispelType / cooldown.
-- Does NOT: Create icons, sort buffers, own layout, or manage animation state.
-- Used by:  TargetRenderer, NameplateRenderer (and future strip renderers).
-- Calls:    AzF.ReverseSweep (aura sweep), AzF.TimerText (timer text),
--           CooldownFrame_SetTimer (cooldowns).
-- ==========================================================================

local IconFill     = AzF.IconFill
local ReverseSweep = AzF.ReverseSweep
local TimerText    = AzF.TimerText

-- -------------------------------------------------------------------------
-- Border color tables
-- -------------------------------------------------------------------------

-- Aura border colors by DBC dispelType enum.
local DISPEL_COLORS = {
    [1] = { 0.2, 0.6, 1.0 },   -- Magic (blue)
    [2] = { 0.6, 0.0, 1.0 },   -- Curse (purple)
    [3] = { 0.6, 0.4, 0.0 },   -- Disease (brown)
    [4] = { 0.0, 0.6, 0.0 },   -- Poison (green)
}
local DEFAULT_AURA_BORDER = { 0.8, 0.0, 0.0 }

-- Static border color for all cooldown icons.
local CD_BORDER = { 0.77, 0.73, 0.63 }

-- Default border color when a slot is hidden / inactive.
local INACTIVE_BORDER = { 0.1, 0.1, 0.1 }

-- -------------------------------------------------------------------------
-- Fill helpers
-- -------------------------------------------------------------------------

-- Fill aura icon slots using reverse sweep (empty-to-filled).
-- Icons beyond `count` are stopped and hidden.
function IconFill:FillAuras(icons, buf, count)
    for i = 1, table.getn(icons) do
        local icon = icons[i]
        if i <= count then
            local entry = buf[i]
            icon.texture:SetTexture(entry.iconTexture)

            -- Border color by dispel type.
            local dc = DISPEL_COLORS[entry.dispelType] or DEFAULT_AURA_BORDER
            icon.border:SetColor(dc[1], dc[2], dc[3])

            if entry.startedAt and entry.expiresAt and entry.expiresAt > entry.startedAt then
                ReverseSweep:Start(icon.model, entry.startedAt, entry.expiresAt - entry.startedAt)
                TimerText:Start(icon.overlay, entry.expiresAt)
            else
                ReverseSweep:Stop(icon.model)
                TimerText:Stop(icon.overlay)
            end
            icon.frame:Show()
        else
            ReverseSweep:Stop(icon.model)
            TimerText:Stop(icon.overlay)
            icon.border:SetColor(INACTIVE_BORDER[1], INACTIVE_BORDER[2], INACTIVE_BORDER[3])
            icon.frame:Hide()
        end
    end
end

-- Fill cooldown icon slots using standard sweep (filled-to-empty).
-- Icons beyond `count` are stopped and hidden.
function IconFill:FillCooldowns(icons, buf, count)
    for i = 1, table.getn(icons) do
        local icon = icons[i]
        if i <= count then
            local entry = buf[i]
            icon.texture:SetTexture(entry.iconTexture)

            -- Static cooldown border color.
            icon.border:SetColor(CD_BORDER[1], CD_BORDER[2], CD_BORDER[3])

            if entry.startedAt and entry.expiresAt and entry.expiresAt > entry.startedAt then
                CooldownFrame_SetTimer(icon.model, entry.startedAt, entry.expiresAt - entry.startedAt, 1)
                TimerText:Start(icon.overlay, entry.expiresAt)
            else
                CooldownFrame_SetTimer(icon.model, 0, 0, 0)
                TimerText:Stop(icon.overlay)
            end
            icon.frame:Show()
        else
            TimerText:Stop(icon.overlay)
            CooldownFrame_SetTimer(icon.model, 0, 0, 0)
            icon.border:SetColor(INACTIVE_BORDER[1], INACTIVE_BORDER[2], INACTIVE_BORDER[3])
            icon.frame:Hide()
        end
    end
end

-- Stop reverse sweeps and timer text on aura icon models (for hide/cleanup paths).
function IconFill:StopAuras(icons, count)
    for i = 1, count do
        ReverseSweep:Stop(icons[i].model)
        TimerText:Stop(icons[i].overlay)
        icons[i].border:SetColor(INACTIVE_BORDER[1], INACTIVE_BORDER[2], INACTIVE_BORDER[3])
    end
end

-- Stop timer text and cooldown sweeps on cooldown icon overlays
-- for hide/cleanup paths.
function IconFill:StopTimers(icons, count)
    for i = 1, count do
        TimerText:Stop(icons[i].overlay)
        CooldownFrame_SetTimer(icons[i].model, 0, 0, 0)
        icons[i].border:SetColor(INACTIVE_BORDER[1], INACTIVE_BORDER[2], INACTIVE_BORDER[3])
    end
end
