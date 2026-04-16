-- ==========================================================================
-- bindings/Nameplates.lua
-- ==========================================================================
-- Purpose:  Discovers Vanilla nameplate frames, maps them to GUIDs, and
--           keeps ActiveFrames updated when plates show or hide.
-- Owns:     The discovery OnUpdate frame, plate registry, and plate<->GUID
--           bidirectional maps.
-- Does NOT: Render anything, track spells, or own gameplay state.
-- Used by:  OnShow/OnHide hooks drive themselves. VisualSync/Renderer call
--           GetPlateForGuid.
-- Calls:    AzF.ActiveFrames (SetSlot, ClearSlot),
--           AzF.VisualSync (OnNameplateShow, OnNameplateHide).
--           WoW API: WorldFrame, plate:GetName(1).
-- ==========================================================================

local Nameplates   = AzF.Nameplates
local ActiveFrames = AzF.ActiveFrames
local VisualSync   = AzF.VisualSync

local registry    = {}   -- [plate] = true   (identity set of discovered plates)
local plateToGuid = {}   -- [plate] = guid
local guidToPlate = {}   -- [guid]  = plate

local lastChildCount = 0

-- ---------------------------------------------------------------------------
-- Nameplate detection
-- ---------------------------------------------------------------------------

local function IsNamePlate(frame)
    if frame:GetObjectType() ~= "Button" then return false end
    local region = frame:GetRegions()
    if not region then return false end
    if not region.GetObjectType then return false end
    if region:GetObjectType() ~= "Texture" then return false end
    return region:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

-- ---------------------------------------------------------------------------
-- Plate bind / unbind
-- ---------------------------------------------------------------------------

local function BindPlate(plate)
    local guid = plate:GetName(1)
    if not guid or guid == "" then return end

    -- If the plate was previously bound to a different GUID, clear the old slot.
    local oldGuid = plateToGuid[plate]
    if oldGuid and oldGuid ~= guid then
        ActiveFrames:ClearSlot(oldGuid, "nameplate")
        guidToPlate[oldGuid] = nil
    end

    plateToGuid[plate] = guid
    guidToPlate[guid]  = plate

    ActiveFrames:SetSlot(guid, "nameplate", plate)
    VisualSync:OnNameplateShow(guid, plate)
end

local function UnbindPlate(plate)
    local guid = plateToGuid[plate]
    if not guid then return end

    ActiveFrames:ClearSlot(guid, "nameplate")
    VisualSync:OnNameplateHide(plate)

    guidToPlate[guid]  = nil
    plateToGuid[plate] = nil
end

-- ---------------------------------------------------------------------------
-- Plate hooks
-- ---------------------------------------------------------------------------

local function HookPlate(plate)
    -- Save-and-chain: preserve any existing scripts for compatibility.
    local origOnShow = plate:GetScript("OnShow")
    plate:SetScript("OnShow", function()
        if origOnShow then origOnShow() end
        BindPlate(this)
    end)

    local origOnHide = plate:GetScript("OnHide")
    plate:SetScript("OnHide", function()
        if origOnHide then origOnHide() end
        UnbindPlate(this)
    end)

    -- Bind immediately if the plate is already visible at discovery time.
    if plate:IsShown() then
        BindPlate(plate)
    end
end

-- ---------------------------------------------------------------------------
-- Discovery frame
-- ---------------------------------------------------------------------------

local discoveryFrame = CreateFrame("Frame")

discoveryFrame:SetScript("OnUpdate", function()
    local count = WorldFrame:GetNumChildren()
    if count == lastChildCount then return end

    local children = { WorldFrame:GetChildren() }
    for i = lastChildCount + 1, count do
        local child = children[i]
        if child and not registry[child] and IsNamePlate(child) then
            registry[child] = true
            HookPlate(child)
        end
    end

    lastChildCount = count
end)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Return the plate frame for a GUID, or nil.
function Nameplates:GetPlateForGuid(guid)
    return guidToPlate[guid]
end

-- Clear all plate state. Called on zone change.
function Nameplates:Wipe()
    for plate, guid in pairs(plateToGuid) do
        ActiveFrames:ClearSlot(guid, "nameplate")
    end
    for k in pairs(plateToGuid) do plateToGuid[k] = nil end
    for k in pairs(guidToPlate) do guidToPlate[k] = nil end
    -- Registry and hooks survive zone changes; plates rebind via OnShow.
end

-- Discovery starts at file load. No additional setup needed.
function Nameplates:Init()
end
