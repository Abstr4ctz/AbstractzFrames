-- ==========================================================================
-- render/CastBar.lua
-- ==========================================================================
-- Purpose:  Shared castbar widget factory and centralized animation driver.
--           Creates castbar StatusBars for any renderer and animates all
--           active castbars from a single OnUpdate frame.
-- Owns:     CastBar:Create factory, animation OnUpdate frame, activeBars
--           set, Refresh/Hide/HideAll logic, spell icon/name resolution.
-- Does NOT: Track cast state, know about GUIDs, or own any renderer layout.
-- Used by:  render/NameplateRenderer.lua; future arena, focus, target
--           castbar, and CastbarHUD renderers.
-- Calls:    WoW API: CreateFrame, GetTime.
--           nampower: GetSpellRecField, GetSpellIconTexture.
-- ==========================================================================

local CastBar = AzF.CastBar

-- Set of currently shown (animating) castbar frames.
local activeBars = {}
local spellMetaCache = {}

-- Single animation frame. Hidden when no castbars are active.
local animFrame = CreateFrame("Frame")
animFrame:Hide()

local function GetSpellMeta(spellId)
    local meta = spellMetaCache[spellId]
    if meta then
        return meta
    end

    local iconId = GetSpellRecField(spellId, "spellIconID")
    meta = {
        icon = (iconId and GetSpellIconTexture(iconId)) or "",
        name = GetSpellRecField(spellId, "name") or "",
    }
    spellMetaCache[spellId] = meta
    return meta
end

-- ---------------------------------------------------------------------------
-- Centralized animation
-- ---------------------------------------------------------------------------

animFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local anyActive = false

    for castBar in pairs(activeBars) do
        local data = castBar.castData
        if not data then
            castBar:SetValue(0)
            castBar.spark:SetPoint("CENTER", castBar, "LEFT", 0, 0)
            castBar:Hide()
            activeBars[castBar] = nil
        elseif now >= data.endTime then
            castBar.castData = nil
            castBar:SetValue(0)
            castBar.spark:SetPoint("CENTER", castBar, "LEFT", 0, 0)
            castBar:Hide()
            activeBars[castBar] = nil
        else
            anyActive = true
            local duration = data.endTime - data.startedAt
            local frac
            if data.isChannel then
                frac = (data.endTime - now) / duration
            else
                frac = (now - data.startedAt) / duration
            end
            castBar:SetValue(frac)
            castBar.spark:SetPoint("CENTER", castBar, "LEFT", frac * castBar:GetWidth(), 0)
        end
    end

    if not anyActive then animFrame:Hide() end
end)

-- ---------------------------------------------------------------------------
-- Factory
-- ---------------------------------------------------------------------------

-- Create a castbar StatusBar with spark, spell icon, and spell name text.
-- Caller is responsible for anchoring and setting frame level.
function CastBar:Create(parent, width, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetWidth(width)
    bar:SetHeight(height)
    bar:SetOrientation("HORIZONTAL")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0.82, 0, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetWidth(8)
    spark:SetHeight(height * 2)
    spark:SetBlendMode("ADD")

    local iconTex = bar:CreateTexture(nil, "OVERLAY")
    iconTex:SetWidth(height + 2)
    iconTex:SetHeight(height + 2)
    iconTex:SetPoint("RIGHT", bar, "LEFT", -1, 0)
    iconTex:SetTexCoord(0.07, 0.9, 0.1, 0.93)

    local castText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castText:SetWidth(width)
    castText:SetHeight(height)
    castText:SetPoint("CENTER", bar, "CENTER", 0, 0)

    bar.spark    = spark
    bar.iconTex  = iconTex
    bar.castText = castText
    bar.castData = nil

    -- Use alpha for visibility instead of Hide/Show. WoW 1.12's StatusBar
    -- does not recalculate fill texture coords across Hide/Show cycles,
    -- causing a one-frame stale-fill flash. Keeping the bar permanently
    -- "shown" at alpha 0 ensures SetValue always updates the texture.
    bar:SetAlpha(0)

    bar.Show = function(self) self:SetAlpha(1) end
    bar.Hide = function(self) self:SetAlpha(0) end

    return bar
end

-- ---------------------------------------------------------------------------
-- Refresh / Hide
-- ---------------------------------------------------------------------------

-- Update a castbar from cast state. Shows the bar and registers for
-- animation if a cast is active; hides and deregisters otherwise.
function CastBar:Refresh(castBar, cast, now)
    if not cast or now >= cast.endTime then
        if castBar.castData or activeBars[castBar] then
            castBar.castData = nil
            castBar:SetValue(0)
            castBar.spark:SetPoint("CENTER", castBar, "LEFT", 0, 0)
            castBar:Hide()
            if activeBars[castBar] then
                activeBars[castBar] = nil
                if not next(activeBars) then animFrame:Hide() end
            end
        end
        return
    end

    local meta = GetSpellMeta(cast.spellId)

    castBar.iconTex:SetTexture(meta.icon)
    castBar.castText:SetText(meta.name)
    castBar.castData = cast

    local duration = cast.endTime - cast.startedAt
    if duration > 0 then
        local frac
        if cast.isChannel then
            frac = (cast.endTime - now) / duration
        else
            frac = (now - cast.startedAt) / duration
        end
        castBar:SetValue(frac)
        castBar.spark:SetPoint("CENTER", castBar, "LEFT", frac * castBar:GetWidth(), 0)
    end

    castBar:Show()

    if not activeBars[castBar] then
        activeBars[castBar] = true
        animFrame:Show()
    end
end

-- Hide a single castbar and deregister from animation.
function CastBar:Hide(castBar)
    castBar.castData = nil
    castBar:SetValue(0)
    castBar.spark:SetPoint("CENTER", castBar, "LEFT", 0, 0)
    castBar:Hide()
    if activeBars[castBar] then
        activeBars[castBar] = nil
        if not next(activeBars) then animFrame:Hide() end
    end
end

-- Hide all active castbars. Used on zone-change wipe.
function CastBar:HideAll()
    for castBar in pairs(activeBars) do
        castBar.castData = nil
        castBar:SetValue(0)
        castBar.spark:SetPoint("CENTER", castBar, "LEFT", 0, 0)
        castBar:Hide()
    end
    activeBars = {}
    animFrame:Hide()
end

-- No-op for lifecycle consistency.
function CastBar:Init()
end
