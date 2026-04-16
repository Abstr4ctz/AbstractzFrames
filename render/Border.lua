-- ==========================================================================
-- render/Border.lua
-- ==========================================================================
-- Purpose:  8-piece beveled border factory. Builds a tintable border frame
--           from a single border texture, split into 4 corners + 4 sides
--           via UV sampling. Matches the enemyFrames visual style.
-- Owns:     Border:Create, border:SetColor, border:SetPadding.
-- Does NOT: Know about icons, sweeps, spells, or aura state.
-- Used by:  render/IconFactory.lua (and future frame builders).
-- Calls:    WoW texture/frame APIs only.
-- ==========================================================================

local Border = AzF.Border

local TEXTURE = [[Interface\AddOns\AbstractzFrames\assets\border.tga]]
local DEFAULT_TCUT = 1 / 4.2

-- Pre-compute UV rectangles for corners and sides from a given cut ratio.
local function GetTexCoords(tcut)
    local corners = {
        { { 0,     tcut, 0,     tcut }, "TOPLEFT" },
        { { 1-tcut, 1,   0,     tcut }, "TOPRIGHT" },
        { { 0,     tcut, 1-tcut, 1   }, "BOTTOMLEFT" },
        { { 1-tcut, 1,   1-tcut, 1   }, "BOTTOMRIGHT" },
    }
    local sides = {
        { 0,     tcut, tcut, 1-tcut },   -- left
        { 1-tcut, 1,   tcut, 1-tcut },   -- right
        { tcut, 1-tcut, 0,     tcut },   -- top
        { tcut, 1-tcut, 1-tcut, 1   },   -- bottom
    }
    return corners, sides
end

-- Create an 8-piece beveled border on `parent`.
-- Returns a frame with :SetColor(r,g,b) and :SetPadding(px) methods.
--
-- @param parent  Frame to overlay the border on.
-- @param size    Corner piece size in pixels (e.g. 14 for nameplate icons).
-- @param tcut    Optional UV cut ratio. Defaults to 1/4.2.
function Border:Create(parent, size, tcut)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)

    local tcutsize = tcut or DEFAULT_TCUT
    local corners, sides = GetTexCoords(tcutsize)

    -- Corner textures
    frame.c = {}
    for i = 1, 4 do
        local c = frame:CreateTexture(nil, "OVERLAY")
        c:SetWidth(size)
        c:SetHeight(size)
        c:SetTexture(TEXTURE)
        c:SetTexCoord(corners[i][1][1], corners[i][1][2],
                      corners[i][1][3], corners[i][1][4])

        local xo = (i == 1 or i == 3) and -1/8 or  1/8
        local yo = (i == 1 or i == 2) and  1/8 or -1/8
        c:SetPoint(corners[i][2], frame, xo * size, yo * size)

        frame.c[i] = c
    end

    -- Side textures (stretched between adjacent corners)
    frame.s = {}
    for i = 1, 4 do
        local s = frame:CreateTexture(nil, "OVERLAY")
        s:SetTexture(TEXTURE)
        s:SetTexCoord(sides[i][1], sides[i][2], sides[i][3], sides[i][4])
        frame.s[i] = s
    end

    -- left
    frame.s[1]:SetPoint("TOPLEFT",     frame.c[1], "BOTTOMLEFT")
    frame.s[1]:SetPoint("BOTTOMRIGHT", frame.c[3], "TOPRIGHT")
    -- right
    frame.s[2]:SetPoint("TOPLEFT",     frame.c[2], "BOTTOMLEFT")
    frame.s[2]:SetPoint("BOTTOMRIGHT", frame.c[4], "TOPRIGHT")
    -- top
    frame.s[3]:SetPoint("TOPLEFT",     frame.c[1], "TOPRIGHT")
    frame.s[3]:SetPoint("BOTTOMRIGHT", frame.c[2], "BOTTOMLEFT")
    -- bottom
    frame.s[4]:SetPoint("TOPLEFT",     frame.c[3], "TOPRIGHT")
    frame.s[4]:SetPoint("BOTTOMRIGHT", frame.c[4], "BOTTOMLEFT")

    -- Cache corner metadata for SetPadding recalculations.
    frame._borderSize    = size
    frame._borderCorners = corners

    -- Tint all 8 pieces.
    function frame:SetColor(r, g, b)
        for j = 1, 4 do
            self.c[j]:SetVertexColor(r, g, b)
            self.s[j]:SetVertexColor(r, g, b)
        end
    end

    -- Adjust corner outward offset for tighter/looser overlap.
    function frame:SetPadding(px)
        local sz = self._borderSize
        local cn = self._borderCorners
        for j = 1, 4 do
            local xo = (j == 1 or j == 3) and -1/8 or  1/8
            local yo = (j == 1 or j == 2) and  1/8 or -1/8
            local padX = (j == 1 or j == 3) and -px or px
            local padY = (j == 1 or j == 2) and  px or -px
            self.c[j]:SetPoint(cn[j][2], self, xo * sz + padX, yo * sz + padY)
        end
    end

    -- Default color: dark gray (matching enemyFrames).
    frame:SetColor(0.1, 0.1, 0.1)

    return frame
end
