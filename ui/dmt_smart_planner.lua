-- =======================================================================
-- DMT Smart Planner: Settler Recommendations & City District Optimizer
-- Author: YAMAEARTH / Antigravity
-- Pure client-side UI script (Single player & Multiplayer safe)
-- Shortcut: SHIFT + A
-- =======================================================================

print("Loading DMT_SmartPlanner.lua");

include("civ6common");
include("InstanceManager");
include("MapTacks");

-- Cache of auto-placed pins
local m_AutoSettlerPins = {};
local m_AutoDistrictPins = {};
local m_LastSettlerUnitID = -1;
local m_LastSettlerPlotIndex = -1;

-- Instance Managers for HUD Panels
local m_SettlerIM = nil;
local m_DistrictIM = nil;

-- Map pin types definition fallback
local MAP_PIN_TYPES = {
    UNKNOWN = "UNKNOWN",
    IMPROVEMENT = "IMPROVEMENT",
    DISTRICT = "DISTRICT",
    WONDER = "WONDER"
};

-- =======================================================================
-- Helper Functions
-- =======================================================================

-- Safe visibility check using PlayersVisibility service
local function IsPlotVisibleOrRevealed(plot, playerID)
    if plot == nil then return false; end
    if PlayersVisibility ~= nil and PlayersVisibility[playerID] ~= nil then
        return PlayersVisibility[playerID]:IsRevealed(plot:GetIndex());
    end
    return true;
end

local function IsAutoSettlerPin(x, y)
    return m_AutoSettlerPins[x .. "_" .. y] == true;
end

local function IsAutoDistrictPin(x, y)
    return m_AutoDistrictPins[x .. "_" .. y] ~= nil;
end

-- Safely look up any pin that actually exists on the map from PlayerConfigurations
local function GetPinAtPlot(playerCfg, px, py)
    if not playerCfg then return nil; end
    local allPins = playerCfg:GetMapPins();
    if allPins ~= nil then
        for _, pin in pairs(allPins) do
            if pin ~= nil and pin:GetHexX() == px and pin:GetHexY() == py then
                return pin;
            end
        end
    end
    return nil;
end

-- Check if a plot already has a user-placed manual pin (which we should NOT overwrite)
local function HasManualPinAtPlot(playerCfg, px, py)
    local existing = GetPinAtPlot(playerCfg, px, py);
    if existing ~= nil then
        local key = px .. "_" .. py;
        if not m_AutoSettlerPins[key] and not m_AutoDistrictPins[key] then
            local name = existing:GetName() or "";
            -- Protect user manual pins while not blocking auto-settler or auto-district pins
            if not name:match("^#%d.*ตั้งเมือง") and not name:match("^%[.-%]%s*#%d") and not name:match("^%[เมือง") then
                return true;
            end
        end
    end
    return false;
end

local m_SettlerPanelDismissedByUser = false;

function OnCloseSettlerPanel()
    m_SettlerPanelDismissedByUser = true;
    if Controls.SettlerRecommendationPanel then
        Controls.SettlerRecommendationPanel:SetHide(true);
    end
    UI.PlaySound("Play_UI_Click");
end

function OnCloseDistrictPanel()
    if Controls.CityDistrictPlanPanel then
        Controls.CityDistrictPlanPanel:SetHide(true);
    end
    UI.PlaySound("Play_UI_Click");
end

local function EnsureInstanceManagers()
    if m_SettlerIM == nil and Controls.SettlerListStack ~= nil then
        m_SettlerIM = InstanceManager:new("SettlerEntryInstance", "EntryBox", Controls.SettlerListStack);
    end
    if Controls.SettlerCloseButton then
        Controls.SettlerCloseButton:RegisterCallback(Mouse.eLClick, OnCloseSettlerPanel);
        Controls.SettlerCloseButton:RegisterCallback(Mouse.eMouseEnter, function()
            UI.PlaySound("Main_Menu_Mouse_Over");
        end);
    end

    if m_DistrictIM == nil and Controls.DistrictListStack ~= nil then
        m_DistrictIM = InstanceManager:new("DistrictEntryInstance", "EntryRoot", Controls.DistrictListStack);
    end
    if Controls.DistrictCloseButton then
        Controls.DistrictCloseButton:RegisterCallback(Mouse.eLClick, OnCloseDistrictPanel);
        Controls.DistrictCloseButton:RegisterCallback(Mouse.eMouseEnter, function()
            UI.PlaySound("Main_Menu_Mouse_Over");
        end);
    end
end

-- Get unique district replacement for local player
function GetPlayerUniqueDistrict(playerID, baseDistrictType)
    if not baseDistrictType or not GameInfo.Districts[baseDistrictType] then
        return baseDistrictType;
    end
    local playerConfig = PlayerConfigurations[playerID];
    if not playerConfig then return baseDistrictType; end

    local civType = playerConfig:GetCivilizationTypeName();
    local leaderType = playerConfig:GetLeaderTypeName();

    for row in GameInfo.DistrictReplaces() do
        if row.ReplacesDistrictType == baseDistrictType then
            local uniqueDistrict = GameInfo.Districts[row.CivUniqueDistrictType];
            if uniqueDistrict and uniqueDistrict.TraitType then
                for civTrait in GameInfo.CivilizationTraits() do
                    if civTrait.CivilizationType == civType and civTrait.TraitType == uniqueDistrict.TraitType then
                        return row.CivUniqueDistrictType;
                    end
                end
                for leaderTrait in GameInfo.LeaderTraits() do
                    if leaderTrait.LeaderType == leaderType and leaderTrait.TraitType == uniqueDistrict.TraitType then
                        return row.CivUniqueDistrictType;
                    end
                end
            end
        end
    end
    return baseDistrictType;
end

-- Get base district type if given a unique district type
function GetBaseDistrictType(districtType)
    if districtType == nil then return nil; end
    if GameInfo.DistrictReplaces then
        for row in GameInfo.DistrictReplaces() do
            if row.CivUniqueDistrictType == districtType then
                return row.ReplacesDistrictType;
            end
        end
    end
    return districtType;
end

-- Check if Government Plaza is already built in the empire
function HasEmpireGovernmentPlaza(playerID)
    local pPlayer = Players[playerID];
    if not pPlayer then return false; end
    local pCities = pPlayer:GetCities();
    if not pCities then return false; end
    for i, pCity in pCities:Members() do
        local pCityDistricts = pCity:GetDistricts();
        if pCityDistricts ~= nil then
            for j, district in pCityDistricts:Members() do
                if district ~= nil and type(district) == "table" and district.GetType ~= nil then
                    local dType = district:GetType();
                    if dType ~= -1 and GameInfo.Districts[dType] ~= nil then
                        if GameInfo.Districts[dType].DistrictType == "DISTRICT_GOVERNMENT" then
                            return true;
                        end
                    end
                end
            end
        end
    end
    return false;
end

-- Check if Diplomatic Quarter is already built in the empire
function HasEmpireDiplomaticQuarter(playerID)
    local pPlayer = Players[playerID];
    if not pPlayer then return false; end
    local pCities = pPlayer:GetCities();
    if not pCities then return false; end
    for i, pCity in pCities:Members() do
        local pCityDistricts = pCity:GetDistricts();
        if pCityDistricts ~= nil then
            for j, district in pCityDistricts:Members() do
                if district ~= nil and type(district) == "table" and district.GetType ~= nil then
                    local dType = district:GetType();
                    if dType ~= -1 and GameInfo.Districts[dType] ~= nil then
                        if GameInfo.Districts[dType].DistrictType == "DISTRICT_DIPLOMATIC_QUARTER" then
                            return true;
                        end
                    end
                end
            end
        end
    end
    return false;
end

local function IsEmpireDistrictAlreadyPlanned(baseDistrictType)
    for key, info in pairs(m_AutoDistrictPins) do
        if type(info) == "table" and (info.BaseDistrictType == baseDistrictType or info.DistrictType == baseDistrictType) then
            return true;
        end
    end
    return false;
end

-- Rule 3: Canal Valid Geometry & 60-degree bend rule
-- Flat land, connects 2 water bodies or 1 water + 1 city center, no sharp bend <= 60 deg (endpoints cannot be adjacent)
local function IsValidCanalPosition(playerID, px, py, cityX, cityY)
    local plot = Map.GetPlot(px, py);
    if plot == nil or plot:IsWater() or plot:IsHills() or plot:IsMountain() then
        return false;
    end

    local adjPlots = Map.GetAdjacentPlots(px, py);
    local connectables = {};

    for _, adj in pairs(adjPlots) do
        if adj ~= nil then
            local isWater = adj:IsWater() and not adj:IsImpassable();
            local isCity = adj:IsCity() or (adj:GetX() == cityX and adj:GetY() == cityY);
            if isWater or isCity then
                table.insert(connectables, {
                    Plot = adj,
                    X = adj:GetX(),
                    Y = adj:GetY(),
                    IsWater = isWater,
                    IsCity = isCity
                });
            end
        end
    end

    -- Must have at least 2 connectable endpoints
    if #connectables < 2 then
        return false;
    end

    -- Find at least one valid pair (A, B)
    for i = 1, #connectables - 1 do
        for j = i + 1, #connectables do
            local a = connectables[i];
            local b = connectables[j];

            -- Rule 3: Must connect 2 water bodies OR 1 water body + 1 City Center
            local hasWater = a.IsWater or b.IsWater;
            local validTypes = (a.IsWater or a.IsCity) and (b.IsWater or b.IsCity);

            if hasWater and validTypes then
                -- Rule 3: No sharp bend <= 60 degrees (A and B cannot be adjacent to each other)
                local distBetweenEndpoints = Map.GetPlotDistance(a.X, a.Y, b.X, b.Y);
                if distBetweenEndpoints >= 2 then
                    return true;
                end
            end
        end
    end

    return false;
end

-- Specialty vs Non-Specialty Districts (Pop Cap distinction)
-- Government Plaza & Diplomatic Quarter do NOT count toward Pop cap (built for free)
-- Aerodrome counts toward Pop cap (Specialty District)
-- Spaceport does NOT count toward Pop cap
local NON_SPECIALTY_DISTRICTS = {
    DISTRICT_AQUEDUCT = true,
    DISTRICT_BATH = true,
    DISTRICT_DAM = true,
    DISTRICT_CANAL = true,
    DISTRICT_NEIGHBORHOOD = true,
    DISTRICT_MBANZA = true,
    DISTRICT_SPACEPORT = true,
    DISTRICT_GOVERNMENT = true,
    DISTRICT_DIPLOMATIC_QUARTER = true
};

local function IsSpecialtyDistrict(districtType, baseDistrictType)
    if (districtType and NON_SPECIALTY_DISTRICTS[districtType]) or (baseDistrictType and NON_SPECIALTY_DISTRICTS[baseDistrictType]) then
        return false;
    end
    return true;
end

-- Fallback table of Bonus Resource Harvest Technologies
local BONUS_HARVEST_TECHS = {
    RESOURCE_BANANAS = "TECH_IRRIGATION",
    RESOURCE_CATTLE = "TECH_ANIMAL_HUSBANDRY",
    RESOURCE_COPPER = "TECH_MINING",
    RESOURCE_CRABS = "TECH_CELESTIAL_NAVIGATION",
    RESOURCE_DEER = "TECH_ANIMAL_HUSBANDRY",
    RESOURCE_FISH = "TECH_CELESTIAL_NAVIGATION",
    RESOURCE_RICE = "TECH_POTTERY",
    RESOURCE_SHEEP = "TECH_ANIMAL_HUSBANDRY",
    RESOURCE_STONE = "TECH_MASONRY",
    RESOURCE_WHEAT = "TECH_POTTERY",
    RESOURCE_MAIZE = "TECH_POTTERY"
};

-- Rule 2: Resource Tile Restrictions (Strictly forbid Luxury, Revealed Strategic, & Unharvestable Bonus resources)
local function HasForbiddenResourceForDistrict(playerID, plot)
    if plot == nil then return false; end
    local rIdx = plot:GetResourceType();
    if rIdx == -1 then return false; end
    local rInfo = GameInfo.Resources[rIdx];
    if rInfo == nil then return false; end

    -- 1. Luxury Resources can NEVER be crushed by districts in Civ 6
    if rInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
        return true;
    end

    -- 2. Strategic Resources revealed by player's researched tech can NEVER be crushed
    if rInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
        local pPlayer = Players[playerID];
        if pPlayer and pPlayer:GetResources() then
            if pPlayer:GetResources():IsResourceVisible(rInfo.Hash) then
                return true;
            end
        else
            return true;
        end
    end

    -- 3. Bonus Resources require their corresponding Harvest Technology to be researched
    if rInfo.ResourceClassType == "RESOURCECLASS_BONUS" then
        local prereqTechType = nil;
        if GameInfo.Resource_Harvests ~= nil then
            for row in GameInfo.Resource_Harvests() do
                if row.ResourceType == rInfo.ResourceType then
                    prereqTechType = row.PrereqTech;
                    break;
                end
            end
        end
        if prereqTechType == nil then
            prereqTechType = BONUS_HARVEST_TECHS[rInfo.ResourceType];
        end

        if prereqTechType ~= nil then
            local techInfo = GameInfo.Technologies[prereqTechType];
            if techInfo ~= nil then
                local pPlayer = Players[playerID];
                if pPlayer and pPlayer:GetTechs() then
                    if not pPlayer:GetTechs():HasTech(techInfo.Index) then
                        -- Player does not have the harvest tech yet! The game forbids placing districts on it!
                        return true;
                    end
                end
            end
        end
    end

    -- 4. Any non-harvestable resource
    if CanHarvestResource ~= nil and not CanHarvestResource(rInfo.ResourceType) then
        return true;
    end

    return false;
end

-- Rule 1: Dam 1-per-river system check across the whole empire/map
local function IsDamAlreadyOnRiver(playerID, px, py)
    if RiverManager == nil then return false; end
    local riverTypeId = RiverManager.GetRiverForFloodplain(px, py);
    if riverTypeId == -1 then return false; end

    -- Check all floodplain plots of this river
    local fpPlots = RiverManager.GetFloodplainPlots(riverTypeId);
    if fpPlots ~= nil then
        for _, plotIndex in ipairs(fpPlots) do
            local p = Map.GetPlotByIndex(plotIndex);
            if p ~= nil then
                local dType = p:GetDistrictType();
                if dType ~= -1 and GameInfo.Districts[dType] ~= nil and GameInfo.Districts[dType].DistrictType == "DISTRICT_DAM" then
                    return true;
                end
                local key = p:GetX() .. "_" .. p:GetY();
                local pin = m_AutoDistrictPins[key];
                if pin ~= nil and (pin.DistrictType == "DISTRICT_DAM" or pin.BaseDistrictType == "DISTRICT_DAM") then
                    return true;
                end
            end
        end
    end

    -- Check m_AutoDistrictPins for any planned Dam on this river
    for key, info in pairs(m_AutoDistrictPins) do
        if type(info) == "table" and (info.DistrictType == "DISTRICT_DAM" or info.BaseDistrictType == "DISTRICT_DAM") then
            local pX = info.PlotX or info.CityX;
            local pY = info.PlotY or info.CityY;
            if pX and pY then
                local rId = RiverManager.GetRiverForFloodplain(pX, pY);
                if rId ~= -1 and rId == riverTypeId then
                    return true;
                end
            end
        end
    end

    return false;
end

-- Rule 4: Dam Placement Restriction (River Floodplains only, FORBID Coastal Floodplains)
local function IsValidRiverFloodplainForDam(plot)
    if plot == nil or plot:IsWater() then return false; end

    -- 1. Gathering Storm Coastal Lowland / Coastal Floodplains check
    -- Coastal lowlands flood from rising sea level / global warming, NOT river flooding!
    if TerrainManager ~= nil and TerrainManager.GetCoastalLowlandType ~= nil then
        local lowlandType = TerrainManager.GetCoastalLowlandType(plot);
        if lowlandType ~= nil and lowlandType ~= -1 then
            return false; -- Coastal Lowland / Coastal Floodplain! Forbidden for Dam!
        end
    end

    -- 2. Must be a valid River Floodplain feature (Grassland, Plains, Desert)
    local fIdx = plot:GetFeatureType();
    if fIdx == -1 then return false; end
    local fInfo = GameInfo.Features[fIdx];
    if fInfo == nil then return false; end
    local fType = fInfo.FeatureType;

    if fType ~= "FEATURE_FLOODPLAINS" and fType ~= "FEATURE_FLOODPLAINS_GRASSLAND" and fType ~= "FEATURE_FLOODPLAINS_PLAINS" then
        return false;
    end

    -- 3. Must have at least 2 river edges
    if plot:GetRiverCrossingCount() < 2 then
        return false;
    end

    return true;
end

-- Rule 4: Vietnam Feature Requirement (Woods / Rainforest / Marsh)
local function IsValidVietnamFeature(plot)
    if plot == nil then return false; end
    local fIdx = plot:GetFeatureType();
    if fIdx ~= -1 and GameInfo.Features[fIdx] ~= nil then
        local fType = GameInfo.Features[fIdx].FeatureType;
        return fType == "FEATURE_FOREST" or fType == "FEATURE_JUNGLE" or fType == "FEATURE_MARSH";
    end
    return false;
end

-- Rule 5: Priority score calculation for sorting build sequence
local function CalculateDistrictPriority(item, cityHasFreshWater)
    local baseType = item.BaseDistrictType;
    local num = item.NumericBonus or 0;
    local score = 50;

    if baseType == "DISTRICT_CAMPUS" then
        score = 92 + num * 4;
    elseif baseType == "DISTRICT_COMMERCIAL_HUB" or baseType == "DISTRICT_HARBOR" then
        score = 88 + num * 3;
    elseif baseType == "DISTRICT_GOVERNMENT" then
        score = 87; -- High priority non-specialty hub boosting all surrounding districts
    elseif baseType == "DISTRICT_HOLY_SITE" then
        score = 86 + num * 3;
    elseif baseType == "DISTRICT_AQUEDUCT" then
        score = not cityHasFreshWater and 87 or 74;
    elseif baseType == "DISTRICT_INDUSTRIAL_ZONE" then
        score = 85 + num * 3;
    elseif baseType == "DISTRICT_DAM" then
        score = 78;
    elseif baseType == "DISTRICT_DIPLOMATIC_QUARTER" then
        score = 76; -- Non-specialty 1-per-empire envoy boost
    elseif baseType == "DISTRICT_ENCAMPMENT" then
        score = 72;
    elseif baseType == "DISTRICT_ENTERTAINMENT_COMPLEX" then
        score = 70;
    elseif baseType == "DISTRICT_THEATER" then
        score = 68 + num * 2;
    elseif baseType == "DISTRICT_CANAL" then
        score = 55;
    elseif baseType == "DISTRICT_NEIGHBORHOOD" then
        score = 45;
    elseif baseType == "DISTRICT_AERODROME" then
        score = 35;
    elseif baseType == "DISTRICT_SPACEPORT" then
        score = 20;
    end
    return score;
end

-- =======================================================================
-- Settler Recommendation & Top 3 Placement
-- =======================================================================

function ClearAutoSettlerPins(playerID)
    if playerID == nil or playerID ~= Game.GetLocalPlayer() then
        playerID = Game.GetLocalPlayer();
    end
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local hasChanges = false;
    local allPins = playerCfg:GetMapPins();
    local pinsToDelete = {};
    if allPins ~= nil then
        for _, pin in pairs(allPins) do
            if pin ~= nil then
                local px, py = pin:GetHexX(), pin:GetHexY();
                local key = px .. "_" .. py;
                local pinName = pin:GetName() or "";
                if m_AutoSettlerPins[key] or pinName:match("^#%d.*ตั้งเมือง") then
                    table.insert(pinsToDelete, { ID = pin:GetID(), Pin = pin, Key = key });
                end
            end
        end
    end

    local deletedIDs = {};
    for _, item in ipairs(pinsToDelete) do
        if item.ID ~= nil and not deletedIDs[item.ID] then
            deletedIDs[item.ID] = true;
            pcall(function() LuaEvents.DMT_MapPinRemoved(item.Pin); end);
            pcall(function() playerCfg:DeleteMapPin(item.ID); end);
            m_AutoSettlerPins[item.Key] = nil;
            hasChanges = true;
        end
    end
    m_AutoSettlerPins = {};

    if hasChanges then
        Network.BroadcastPlayerInfo();
        LuaEvents.DMT_RefreshMapPins();
    end
end

function IsValidCitySettlePlot(playerID, pPlot)
    if pPlot == nil then return false; end
    if not IsPlotVisibleOrRevealed(pPlot, playerID) then return false; end
    if pPlot:IsWater() then return false; end
    if pPlot:IsImpassable() then return false; end
    if pPlot:IsMountain() then return false; end
    if pPlot:IsCity() then return false; end

    if pPlot:IsOwned() and pPlot:GetOwner() ~= playerID then
        return false;
    end

    local px, py = pPlot:GetX(), pPlot:GetY();
    local minDistance = 3;
    local players = Game.GetPlayers{Alive = true};
    for _, player in ipairs(players) do
        local pCities = player:GetCities();
        if pCities ~= nil then
            for i, pCity in pCities:Members() do
                local dist = Map.GetPlotDistance(px, py, pCity:GetX(), pCity:GetY());
                if dist <= minDistance then
                    return false;
                end
            end
        end
    end

    return true;
end

local function PlayerHasResource(player, resIndex)
    if player == nil then return false; end
    local pRes = player:GetResources();
    if pRes ~= nil then
        if pRes.GetResourceAmount ~= nil then
            local amt = pRes:GetResourceAmount(resIndex);
            if amt ~= nil and amt > 0 then return true; end
        end
        if pRes.HasResource ~= nil and pRes:HasResource(resIndex) then
            return true;
        end
    end
    -- Also check if any existing owned plot in the empire already contains this resource
    local pCities = player:GetCities();
    if pCities ~= nil then
        for _, city in pCities:Members() do
            local plots = GetPlotsWithinXTiles(city:GetX(), city:GetY(), 3);
            for _, plot in ipairs(plots) do
                if plot:IsOwned() and plot:GetOwner() == player:GetID() then
                    if plot:GetResourceType() == resIndex then
                        return true;
                    end
                end
            end
        end
    end
    return false;
end

-- Rule 1 (Gathering Storm / Rise & Fall): Loyalty Pressure from nearby foreign cities
local function GetPlotLoyaltyPressure(plot)
    if plot == nil then return 0; end
    if Map ~= nil and Map.GetContinentPlotsLoyalty ~= nil then
        local pcallOk, loyaltyTable = pcall(function() return Map.GetContinentPlotsLoyalty(); end);
        if pcallOk and loyaltyTable ~= nil then
            local val = loyaltyTable[plot:GetIndex()];
            if val ~= nil and type(val) == "number" then
                return val;
            end
        end
    end
    return 0;
end

function ScoreSettlerPlot(playerID, pPlot, settlerX, settlerY, grandAIPlots)
    local score = 0;
    local px, py = pPlot:GetX(), pPlot:GetY();
    local reasons = {};
    local waterTag = "ไม่มีน้ำ (2 Housing)";

    -- 0. Loyalty Pressure Check (Strictly forbid settling if loyalty pressure is critically negative)
    local loyaltyVal = GetPlotLoyaltyPressure(pPlot);
    if loyaltyVal <= -10 then
        -- Critical loyalty pressure! City will rebel into a Free City rapidly. Strictly FORBIDDEN!
        return -9999, waterTag, {string.format("แรงกดดัน Loyalty วิกฤต (%d/เทิร์น) เสี่ยงเมืองแตกเป็น Free City", loyaltyVal)};
    elseif loyaltyVal < 0 then
        -- Moderate loyalty pressure: penalize score heavily (-2.5 per negative loyalty point)
        score = score + (loyaltyVal * 2.5);
        table.insert(reasons, string.format("แรงกดดัน Loyalty (%d/เทิร์น)", loyaltyVal));
    end

    -- 1. Water & Housing (Heavily weighted over distance: Fresh Water +32 vs No Water -25)
    if pPlot:IsFreshWater() then
        score = score + 32;
        waterTag = "น้ำจืด (+3 Housing)";
        table.insert(reasons, "แหล่งน้ำจืด (Housing 5)");
    elseif pPlot:IsCoastalLand() then
        score = score + 14;
        waterTag = "ชายฝั่ง (+1 Housing)";
        table.insert(reasons, "ติดชายฝั่ง (Housing 3)");
    else
        score = score - 25;
        waterTag = "ไม่มีน้ำ (2 Housing)";
        table.insert(reasons, "แล้งน้ำ (-25 Housing วิกฤต)");
    end

    -- 2. City Center Tile Quality
    local terrainIndex = pPlot:GetTerrainType();
    local terrainInfo = GameInfo.Terrains[terrainIndex];
    if terrainInfo ~= nil and terrainInfo.Hills then
        if terrainInfo.TerrainType == "TERRAIN_PLAINS_HILLS" then
            score = score + 12;
            table.insert(reasons, "Plains Hills (+1 Prod ฐาน & พลังป้องกัน)");
        else
            score = score + 5;
            table.insert(reasons, "เนินเขา (+3 พลังป้องกัน)");
        end
    end

    local resIndex = pPlot:GetResourceType();
    if resIndex ~= -1 then
        local resInfo = GameInfo.Resources[resIndex];
        if resInfo ~= nil then
            if resInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                score = score + 8;
                table.insert(reasons, "Luxury ในช่องเมือง: " .. Locale.Lookup(resInfo.Name));
            elseif resInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                score = score + 6;
                table.insert(reasons, "Strategic ในช่องเมือง: " .. Locale.Lookup(resInfo.Name));
            end
        end
    end

    -- 3. Ring 1 Yields (6 hexes)
    local ring1Plots = Map.GetAdjacentPlots(px, py);
    for _, adjPlot in pairs(ring1Plots) do
        if adjPlot ~= nil and IsPlotVisibleOrRevealed(adjPlot, playerID) and not adjPlot:IsImpassable() then
            local f = adjPlot:GetYield(GameInfo.Yields["YIELD_FOOD"].Index);
            local p = adjPlot:GetYield(GameInfo.Yields["YIELD_PRODUCTION"].Index);
            local g = adjPlot:GetYield(GameInfo.Yields["YIELD_GOLD"].Index);
            local s = adjPlot:GetYield(GameInfo.Yields["YIELD_SCIENCE"].Index);
            local c = adjPlot:GetYield(GameInfo.Yields["YIELD_CULTURE"].Index);
            local faith = adjPlot:GetYield(GameInfo.Yields["YIELD_FAITH"].Index);

            if f >= 3 then score = score + 5; else score = score + (f * 1.5); end
            if p >= 2 then score = score + 6; else score = score + (p * 2.0); end
            score = score + (s * 2.5) + (c * 2.5) + (faith * 2.0) + (g * 0.5);

            local rIndex = adjPlot:GetResourceType();
            if rIndex ~= -1 then
                local rInfo = GameInfo.Resources[rIndex];
                if rInfo ~= nil then
                    if rInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                        score = score + 7;
                    elseif rInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                        score = score + 5;
                    else
                        score = score + 3;
                    end
                end
            end

            local featIndex = adjPlot:GetFeatureType();
            if featIndex ~= -1 then
                local featInfo = GameInfo.Features[featIndex];
                if featInfo ~= nil then
                    if featInfo.NaturalWonder then
                        score = score + 14;
                    elseif featInfo.FeatureType == "FEATURE_GEOTHERMAL_FISSURE" or featInfo.FeatureType == "FEATURE_REEF" then
                        score = score + 4;
                    elseif featInfo.FeatureType == "FEATURE_FOREST" or featInfo.FeatureType == "FEATURE_JUNGLE" or featInfo.FeatureType == "FEATURE_MARSH" then
                        score = score + 2;
                    end
                end
            end

            if adjPlot:IsMountain() then
                score = score + 2.5;
            end
        end
    end

    -- 4. Ring 2 Yields (12 hexes)
    local allWithin2 = GetPlotsWithinXTiles(px, py, 2);
    for _, plot2 in ipairs(allWithin2) do
        local dist = Map.GetPlotDistance(px, py, plot2:GetX(), plot2:GetY());
        if dist == 2 and IsPlotVisibleOrRevealed(plot2, playerID) and not plot2:IsImpassable() then
            local f = plot2:GetYield(GameInfo.Yields["YIELD_FOOD"].Index);
            local p = plot2:GetYield(GameInfo.Yields["YIELD_PRODUCTION"].Index);
            score = score + (f * 0.8) + (p * 1.0);

            local rIndex = plot2:GetResourceType();
            if rIndex ~= -1 then
                local rInfo = GameInfo.Resources[rIndex];
                if rInfo ~= nil then
                    if rInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then score = score + 4;
                    elseif rInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then score = score + 3; end
                end
            end

            local featIndex = plot2:GetFeatureType();
            if featIndex ~= -1 and GameInfo.Features[featIndex] and GameInfo.Features[featIndex].NaturalWonder then
                score = score + 10;
            end
        end
    end

    -- 5. Movement Distance Penalty
    local moveDist = Map.GetPlotDistance(settlerX, settlerY, px, py);
    if moveDist == 0 then
        score = score + 0;
    elseif moveDist == 1 then
        score = score - 2;
    elseif moveDist == 2 then
        score = score - 5;
    elseif moveDist == 3 then
        score = score - 9;
    else
        score = score - (9 + (moveDist - 3) * 4);
    end

    -- 6. Firaxis AI Bonus
    if grandAIPlots[pPlot:GetIndex()] then
        score = score + 10;
        table.insert(reasons, "AI แนะนำ");
    end

    -- 7. Subsequent Settler Distance Scoring to Existing Friendly Cities
    local pPlayer = Players[playerID];
    local pCities = pPlayer and pPlayer:GetCities();
    local cityCount = pCities and pCities:GetCount() or 0;

    if cityCount >= 1 then
        local minCityDist = 999;
        local nearestCity = nil;
        for _, city in pCities:Members() do
            local d = Map.GetPlotDistance(px, py, city:GetX(), city:GetY());
            if d < minCityDist then
                minCityDist = d;
                nearestCity = city;
            end
        end

        local nearestCityName = nearestCity and Locale.Lookup(nearestCity:GetName()) or "เมืองเดิม";

        -- Check Rings 1-3 for any Luxury or Strategic resource the empire does NOT possess yet
        local hasNewResource = false;
        local newResNames = {};
        local newResSeen = {};
        local ring3Plots = GetPlotsWithinXTiles(px, py, 3);

        for _, p in ipairs(ring3Plots) do
            local rIdx = p:GetResourceType();
            if rIdx ~= -1 and not newResSeen[rIdx] then
                local rInfo = GameInfo.Resources[rIdx];
                if rInfo ~= nil then
                    local isLux = (rInfo.ResourceClassType == "RESOURCECLASS_LUXURY");
                    local isStrat = (rInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC");
                    if isLux or isStrat then
                        local isVisible = true;
                        if isStrat and pPlayer and pPlayer:GetResources() then
                            isVisible = pPlayer:GetResources():IsResourceVisible(rInfo.Hash);
                        end
                        if isVisible and not PlayerHasResource(pPlayer, rInfo.Index) then
                            hasNewResource = true;
                            newResSeen[rIdx] = true;
                            table.insert(newResNames, Locale.Lookup(rInfo.Name));
                        end
                    end
                end
            end
        end

        -- Distance Scoring Logic:
        -- dist < 4: Rejected by engine (cut off)
        -- dist == 4 or 5: +15 pts (Golden distance: AoE 6-tile radius buffs & district combos)
        -- dist == 6: +5 pts (Standard workable distance)
        -- dist >= 7: -10 pts (Too far from empire)
        -- Exception: If Rings 1-3 have unowned Luxury or Strategic, +20 pts compensation for claiming new resource
        if minCityDist < 4 then
            return -9999, waterTag, {"ระยะใกล้เมืองเกินไป (< 4 ช่อง)"};
        elseif minCityDist == 4 or minCityDist == 5 then
            score = score + 15;
            table.insert(reasons, string.format("ระยะทองคำ %d ช่องจาก %s (+15)", minCityDist, nearestCityName));
            if hasNewResource then
                score = score + 10;
                table.insert(reasons, "เคลมแร่ใหม่ของอาณาจักร: " .. table.concat(newResNames, ", "));
            end
        elseif minCityDist == 6 then
            score = score + 5;
            table.insert(reasons, string.format("ระยะมาตรฐาน 6 ช่องจาก %s (+5)", nearestCityName));
            if hasNewResource then
                score = score + 10;
                table.insert(reasons, "เคลมแร่ใหม่ของอาณาจักร: " .. table.concat(newResNames, ", "));
            end
        else -- minCityDist >= 7
            score = score - 10;
            table.insert(reasons, string.format("ระยะห่างเมืองเดิม %d ช่อง (-10)", minCityDist));
            if hasNewResource then
                if loyaltyVal >= -5 then
                    score = score + 20; -- Exception: +20 compensation for claiming new resource far away
                    table.insert(reasons, "เคลมแร่ใหม่ชดเชยระยะไกล (+20): " .. table.concat(newResNames, ", "));
                else
                    table.insert(reasons, "เคลมแร่ใหม่แต่ติด Loyalty เสี่ยง (งดบวกชดเชย)");
                end
            end
        end
    end

    return math.floor(score + 0.5), waterTag, reasons;
end

function RecommendSettlerSpots(playerID, pUnit, bForceRefresh)
    if playerID ~= Game.GetLocalPlayer() then return; end
    if pUnit == nil then return; end

    EnsureInstanceManagers();

    local settlerX, settlerY = pUnit:GetX(), pUnit:GetY();
    local settlerPlotIndex = Map.GetPlot(settlerX, settlerY):GetIndex();

    if not bForceRefresh and m_LastSettlerUnitID == pUnit:GetID() and m_LastSettlerPlotIndex == settlerPlotIndex and next(m_AutoSettlerPins) ~= nil then
        if Controls.SettlerRecommendationPanel then
            Controls.SettlerRecommendationPanel:SetHide(false);
        end
        return;
    end

    m_LastSettlerUnitID = pUnit:GetID();
    m_LastSettlerPlotIndex = settlerPlotIndex;

    ClearAutoSettlerPins(playerID);

    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    local grandAIPlots = {};
    local pGrandAI = pPlayer:GetGrandStrategicAI();
    if pGrandAI ~= nil then
        local pSettlementRecommendations = pGrandAI:GetSettlementRecommendations(10);
        if pSettlementRecommendations ~= nil then
            for _, kRec in pairs(pSettlementRecommendations) do
                if kRec.SettlingLocation ~= nil then
                    grandAIPlots[kRec.SettlingLocation] = true;
                end
            end
        end
    end

    local candidates = {};
    local searchPlots = {};
    local pCities = pPlayer:GetCities();
    local cityCount = pCities and pCities:GetCount() or 0;

    if cityCount >= 1 then
        -- Anchor candidate scan to existing friendly City Centers (rings 4 to 7)
        local seenPlots = {};
        for _, city in pCities:Members() do
            local cx, cy = city:GetX(), city:GetY();
            local cityPlots = GetPlotsWithinXTiles(cx, cy, 7);
            for _, cp in ipairs(cityPlots) do
                local d = Map.GetPlotDistance(cx, cy, cp:GetX(), cp:GetY());
                if d >= 4 and d <= 7 then
                    local idx = cp:GetIndex();
                    if not seenPlots[idx] then
                        seenPlots[idx] = true;
                        table.insert(searchPlots, cp);
                    end
                end
            end
        end
        -- Also include plots within 4 tiles of the Settler unit to cover its immediate surroundings
        local settlerSurroundings = GetPlotsWithinXTiles(settlerX, settlerY, 4);
        for _, sp in ipairs(settlerSurroundings) do
            local idx = sp:GetIndex();
            if not seenPlots[idx] then
                seenPlots[idx] = true;
                table.insert(searchPlots, sp);
            end
        end
    else
        -- First city (turn 1): scan radius 5 around the Settler unit
        searchPlots = GetPlotsWithinXTiles(settlerX, settlerY, 5);
    end

    for plotIdx, _ in pairs(grandAIPlots) do
        local aiPlot = Map.GetPlotByIndex(plotIdx);
        if aiPlot ~= nil then table.insert(searchPlots, aiPlot); end
    end

    local visited = {};
    for _, plot in ipairs(searchPlots) do
        local pIdx = plot:GetIndex();
        if not visited[pIdx] then
            visited[pIdx] = true;
            if IsValidCitySettlePlot(playerID, plot) then
                local score, waterTag, reasons = ScoreSettlerPlot(playerID, plot, settlerX, settlerY, grandAIPlots);
                if score > -9000 then
                    table.insert(candidates, {
                        Plot = plot,
                        Score = score,
                        WaterTag = waterTag,
                        Reasons = reasons
                    });
                end
            end
        end
    end

    if #candidates == 0 then
        print("DMT Smart Planner: No valid settler locations found nearby.");
        return;
    end

    table.sort(candidates, function(a, b) return a.Score > b.Score; end);

    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    -- Populate HUD UI Panel
    if m_SettlerIM ~= nil then
        m_SettlerIM:ResetInstances();
    end

    local topCount = math.min(3, #candidates);
    for rank = 1, topCount do
        local candidate = candidates[rank];
        local px, py = candidate.Plot:GetX(), candidate.Plot:GetY();

        -- 1. Create On-Screen UI Card Entry
        if m_SettlerIM ~= nil then
            local uiEntry = m_SettlerIM:GetInstance();
            uiEntry.RankLabel:SetText("#" .. rank);
            uiEntry.ScoreLabel:SetText(candidate.Score .. " คะแนน");
            uiEntry.WaterLabel:SetText(candidate.WaterTag);
            local detailsText = table.concat(candidate.Reasons, " • ");
            if detailsText == "" then detailsText = "ตำแหน่งมาตรฐาน"; end
            uiEntry.DetailsLabel:SetText(detailsText);
            uiEntry.LookAtButton:RegisterCallback(Mouse.eLClick, function()
                UI.LookAtPlot(px, py);
            end);
        end

        -- 2. Place Map Pin Tack on the World Map
        if not HasManualPinAtPlot(playerCfg, px, py) then
            local pinName = string.format("#%d ตั้งเมือง [%d คะแนน]", rank, candidate.Score);
            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                pin:SetName(pinName);
                pin:SetIconName("ICON_DISTRICT_CITY_CENTER");
                pin:SetVisibility(playerID);

                m_AutoSettlerPins[px .. "_" .. py] = true;
                LuaEvents.DMT_MapPinAdded(pin);
            end
        end
    end

    Network.BroadcastPlayerInfo();
    LuaEvents.DMT_RefreshMapPins();

    if Controls.SettlerRecommendationPanel then
        Controls.SettlerRecommendationPanel:SetHide(false);
    end

    UI.PlaySound("Map_Pin_Add");
    print(string.format("DMT Smart Planner: Displayed UI and pinned %d spots for Settler at (%d, %d)", topCount, settlerX, settlerY));
end

-- =======================================================================
-- City District Boost Optimizer
-- =======================================================================

function ClearAutoDistrictsForCity(playerID, cityX, cityY)
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local cityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local cityPlotSet = {};
    for _, plot in ipairs(cityPlots) do
        cityPlotSet[plot:GetX() .. "_" .. plot:GetY()] = true;
    end

    local hasChanges = false;
    local allPins = playerCfg:GetMapPins();
    local pinsToDelete = {};
    if allPins ~= nil then
        for _, pin in pairs(allPins) do
            if pin ~= nil then
                local px, py = pin:GetHexX(), pin:GetHexY();
                local key = px .. "_" .. py;
                local pinName = pin:GetName() or "";
                local isAutoPin = (m_AutoDistrictPins[key] ~= nil) or pinName:match("^%[.-%]%s*#%d") or pinName:match("^%[เมือง");
                if cityPlotSet[key] and isAutoPin then
                    table.insert(pinsToDelete, { ID = pin:GetID(), Pin = pin, Key = key });
                end
            end
        end
    end

    local deletedIDs = {};
    for _, item in ipairs(pinsToDelete) do
        if item.ID ~= nil and not deletedIDs[item.ID] then
            deletedIDs[item.ID] = true;
            pcall(function() LuaEvents.DMT_MapPinRemoved(item.Pin); end);
            pcall(function() playerCfg:DeleteMapPin(item.ID); end);
            m_AutoDistrictPins[item.Key] = nil;
            hasChanges = true;
        end
    end

    if hasChanges then
        Network.BroadcastPlayerInfo();
        LuaEvents.DMT_RefreshMapPins();
    end
end

local function GetFallbackCityName(playerID, cityIndex)
    local playerConfig = PlayerConfigurations[playerID];
    if playerConfig then
        local civTypeName = playerConfig:GetCivilizationTypeName();
        if civTypeName and GameInfo.CityNames then
            local count = 0;
            local targetIdx = cityIndex or 1;
            for row in GameInfo.CityNames() do
                if row.CivilizationType == civTypeName then
                    count = count + 1;
                    if count == targetIdx then
                        local n = Locale.Lookup(row.CityName);
                        if n and n ~= "" then return n; end
                    end
                end
            end
        end
        local civDesc = playerConfig:GetCivilizationDescription();
        if civDesc then
            local cd = Locale.Lookup(civDesc);
            if cd and cd ~= "" then return cd; end
        end
        local leaderName = playerConfig:GetLeaderName();
        if leaderName then
            local ln = Locale.Lookup(leaderName);
            if ln and ln ~= "" then return ln; end
        end
    end
    return "Capital";
end

local m_LastOptimizedCities = {};
function OptimizeCityDistricts(playerID, cityX, cityY, cityID, bForce)
    if playerID ~= Game.GetLocalPlayer() then return; end
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end
    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    local currentTurn = Game.GetCurrentGameTurn();
    local cityKey = tostring(cityX) .. "_" .. tostring(cityY);
    if not bForce and m_LastOptimizedCities[cityKey] == currentTurn then
        print(string.format("DMT Smart Planner: Skipping redundant district optimization for city at (%s) on turn %d", cityKey, currentTurn));
        return;
    end
    m_LastOptimizedCities[cityKey] = currentTurn;

    EnsureInstanceManagers();

    -- Determine City Information (Name, Capital status, CityID)
    local pCity = nil;
    if cityID ~= nil and cityID ~= -1 and pPlayer:GetCities() ~= nil then
        pCity = pPlayer:GetCities():FindID(cityID);
    end
    if pCity == nil and CityManager ~= nil and CityManager.GetCity ~= nil and cityID ~= nil and cityID ~= -1 then
        pCity = CityManager.GetCity(playerID, cityID);
    end
    if pCity == nil and CityManager ~= nil and CityManager.GetCityAt ~= nil then
        pCity = CityManager.GetCityAt(cityX, cityY);
    end
    if pCity == nil and Cities ~= nil and Cities.GetCityInPlot ~= nil then
        pCity = Cities.GetCityInPlot(cityX, cityY);
    end
    if pCity == nil and pPlayer:GetCities() ~= nil then
        for _, city in pPlayer:GetCities():Members() do
            if city:GetX() == cityX and city:GetY() == cityY then
                pCity = city;
                break;
            end
        end
    end
    if pCity == nil and pPlayer:GetCities() ~= nil then
        local closestCity = nil;
        local minDist = 999;
        for _, city in pPlayer:GetCities():Members() do
            local d = Map.GetPlotDistance(city:GetX(), city:GetY(), cityX, cityY);
            if d < minDist then
                minDist = d;
                closestCity = city;
            end
        end
        if closestCity ~= nil and minDist <= 1 then
            pCity = closestCity;
        end
    end

    local isCapital = false;
    local cityName = "";
    if pCity ~= nil then
        local rawName = pCity:GetName();
        if rawName ~= nil and rawName ~= "" then
            cityName = Locale.Lookup(rawName);
        end
        isCapital = pCity:IsCapital();
        cityID = pCity:GetID();
    end

    if cityName == nil or cityName == "" or cityName == "เมือง" then
        local numCities = (pPlayer:GetCities() and pPlayer:GetCities():GetCount()) or 1;
        cityName = GetFallbackCityName(playerID, numCities);
    end

    print(string.format("DMT Smart Planner: Optimizing districts for [%s] at (%d, %d)", cityName, cityX, cityY));

    ClearAutoSettlerPins(playerID);
    if Controls.SettlerRecommendationPanel then
        Controls.SettlerRecommendationPanel:SetHide(true);
    end

    ClearAutoDistrictsForCity(playerID, cityX, cityY);

    -- Rule 3: Enforce Workable Range (1 - 3 tiles strictly)
    local allCityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local candidatePlots = {};
    local occupiedPlots = {};

    occupiedPlots[Map.GetPlot(cityX, cityY):GetIndex()] = true;

    for _, plot in ipairs(allCityPlots) do
        local pIdx = plot:GetIndex();
        local px, py = plot:GetX(), plot:GetY();

        local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
        local isOutOfRange = (distFromCity < 1 or distFromCity > 3);
        local hasExistingDistrict = plot:GetDistrictType() ~= -1 or plot:IsCity();
        local isForeignOwned = plot:IsOwned() and plot:GetOwner() ~= playerID;
        local isImpassable = plot:IsImpassable() or not IsPlotVisibleOrRevealed(plot, playerID);
        local hasManualPin = HasManualPinAtPlot(playerCfg, px, py);
        -- Rule 2: Exclude Luxury Resources & Revealed Strategic Resources
        local hasForbiddenRes = HasForbiddenResourceForDistrict(playerID, plot);

        if isOutOfRange or hasExistingDistrict or isForeignOwned or isImpassable or hasManualPin or hasForbiddenRes then
            occupiedPlots[pIdx] = true;
        else
            table.insert(candidatePlots, plot);
        end
    end

    local distAqueduct      = GetPlayerUniqueDistrict(playerID, "DISTRICT_AQUEDUCT");
    local distDam           = GetPlayerUniqueDistrict(playerID, "DISTRICT_DAM");
    local distCanal         = GetPlayerUniqueDistrict(playerID, "DISTRICT_CANAL");
    local distIZ            = GetPlayerUniqueDistrict(playerID, "DISTRICT_INDUSTRIAL_ZONE");
    local distHarbor        = GetPlayerUniqueDistrict(playerID, "DISTRICT_HARBOR");
    local distCommHub       = GetPlayerUniqueDistrict(playerID, "DISTRICT_COMMERCIAL_HUB");
    local distCampus        = GetPlayerUniqueDistrict(playerID, "DISTRICT_CAMPUS");
    local distHolySite      = GetPlayerUniqueDistrict(playerID, "DISTRICT_HOLY_SITE");
    local distEntertainment = GetPlayerUniqueDistrict(playerID, "DISTRICT_ENTERTAINMENT_COMPLEX");
    local distTheater       = GetPlayerUniqueDistrict(playerID, "DISTRICT_THEATER");
    local distGovPlaza      = GetPlayerUniqueDistrict(playerID, "DISTRICT_GOVERNMENT");
    local distDiploQuarter  = GetPlayerUniqueDistrict(playerID, "DISTRICT_DIPLOMATIC_QUARTER");
    local distEncampment    = GetPlayerUniqueDistrict(playerID, "DISTRICT_ENCAMPMENT");
    local distNeighborhood  = GetPlayerUniqueDistrict(playerID, "DISTRICT_NEIGHBORHOOD");
    local distAerodrome     = GetPlayerUniqueDistrict(playerID, "DISTRICT_AERODROME");
    local distSpaceport     = GetPlayerUniqueDistrict(playerID, "DISTRICT_SPACEPORT");

    -- Rule 4: Civilization and Unique District Detection
    local playerConfig = PlayerConfigurations[playerID];
    local civType = playerConfig and playerConfig:GetCivilizationTypeName() or "";
    local isVietnam = (civType == "CIVILIZATION_VIETNAM" or distEncampment == "DISTRICT_THANH");
    local isKorea = (civType == "CIVILIZATION_KOREA" or distCampus == "DISTRICT_SEOWON");
    local isGaul = (civType == "CIVILIZATION_GAUL" or distIZ == "DISTRICT_OPPIDUM");
    local isKongo = (civType == "CIVILIZATION_KONGO" or distNeighborhood == "DISTRICT_MBANZA");
    local isGermany = (civType == "CIVILIZATION_GERMANY" or distIZ == "DISTRICT_HANSA");
    local isRome = (civType == "CIVILIZATION_ROME" or distAqueduct == "DISTRICT_BATH");
    local cityPlot = Map.GetPlot(cityX, cityY);
    local cityHasFreshWater = (cityPlot ~= nil) and cityPlot:IsFreshWater();

    -- Identify already constructed or in-progress districts for this city
    local existingCityDistricts = {};        -- map: distTypeName -> pPlot
    local existingDistrictsByBase = {};      -- map: baseDistTypeName -> pPlot

    local function RegisterBuiltDistrict(dTypeName, plot)
        if dTypeName == nil or dTypeName == "DISTRICT_CITY_CENTER" or dTypeName == "DISTRICT_WONDER" then return; end
        existingCityDistricts[dTypeName] = plot;
        local baseType = GetBaseDistrictType(dTypeName);
        existingDistrictsByBase[baseType] = plot;
        existingDistrictsByBase[dTypeName] = plot;
        occupiedPlots[plot:GetIndex()] = true;
    end

    if pCity ~= nil and pCity:GetDistricts() ~= nil then
        for _, pDistrict in pCity:GetDistricts():Members() do
            if pDistrict ~= nil and pDistrict.GetType ~= nil then
                local dType = pDistrict:GetType();
                if dType ~= -1 and GameInfo.Districts[dType] ~= nil then
                    local dPlot = Map.GetPlot(pDistrict:GetX(), pDistrict:GetY());
                    if dPlot ~= nil then
                        RegisterBuiltDistrict(GameInfo.Districts[dType].DistrictType, dPlot);
                    end
                end
            end
        end
    end

    for _, plot in ipairs(allCityPlots) do
        if plot:IsOwned() and plot:GetOwner() == playerID then
            local dType = plot:GetDistrictType();
            if dType ~= -1 and GameInfo.Districts[dType] ~= nil then
                local dTypeName = GameInfo.Districts[dType].DistrictType;
                if dTypeName ~= "DISTRICT_CITY_CENTER" and dTypeName ~= "DISTRICT_WONDER" then
                    local plotCity = (Cities and Cities.GetPlotPurchaseCity) and Cities.GetPlotPurchaseCity(plot) or nil;
                    local bBelongs = (plotCity ~= nil and pCity ~= nil and plotCity:GetID() == pCity:GetID()) or
                                     (pCity ~= nil and Map.GetPlotDistance(cityX, cityY, plot:GetX(), plot:GetY()) <= 3);
                    if bBelongs then
                        RegisterBuiltDistrict(dTypeName, plot);
                    end
                end
            end
            -- Also detect user manual district pins placed on plots
            if HasManualPinAtPlot(playerCfg, plot:GetX(), plot:GetY()) then
                local pin = GetPinAtPlot(playerCfg, plot:GetX(), plot:GetY());
                if pin ~= nil then
                    local iconName = pin:GetIconName() or "";
                    if iconName:match("^ICON_DISTRICT_") then
                        local dTypeName = iconName:gsub("^ICON_", "");
                        if dTypeName ~= "DISTRICT_CITY_CENTER" and dTypeName ~= "DISTRICT_WONDER" then
                            RegisterBuiltDistrict(dTypeName, plot);
                        end
                    end
                end
            end
        end
    end

    local function CityHasDistrict(targetType)
        if targetType == nil then return false; end
        if existingCityDistricts[targetType] ~= nil or existingDistrictsByBase[targetType] ~= nil then
            return true;
        end
        local baseType = GetBaseDistrictType(targetType);
        if baseType and (existingCityDistricts[baseType] ~= nil or existingDistrictsByBase[baseType] ~= nil) then
            return true;
        end
        local uniqueType = GetPlayerUniqueDistrict(playerID, targetType);
        if uniqueType and (existingCityDistricts[uniqueType] ~= nil or existingDistrictsByBase[uniqueType] ~= nil) then
            return true;
        end
        return false;
    end

    local function GetExistingDistrictPlot(targetType)
        if targetType == nil then return nil; end
        if existingCityDistricts[targetType] ~= nil then return existingCityDistricts[targetType]; end
        if existingDistrictsByBase[targetType] ~= nil then return existingDistrictsByBase[targetType]; end
        local baseType = GetBaseDistrictType(targetType);
        if baseType and existingDistrictsByBase[baseType] ~= nil then return existingDistrictsByBase[baseType]; end
        local uniqueType = GetPlayerUniqueDistrict(playerID, targetType);
        if uniqueType and existingCityDistricts[uniqueType] ~= nil then return existingCityDistricts[uniqueType]; end
        return nil;
    end

    local specialtyBaseTypes = {
        DISTRICT_CAMPUS = true,
        DISTRICT_HOLY_SITE = true,
        DISTRICT_COMMERCIAL_HUB = true,
        DISTRICT_HARBOR = true,
        DISTRICT_ENCAMPMENT = true,
        DISTRICT_INDUSTRIAL_ZONE = true,
        DISTRICT_THEATER = true,
        DISTRICT_ENTERTAINMENT_COMPLEX = true,
        DISTRICT_WATER_ENTERTAINMENT_COMPLEX = true,
        DISTRICT_AERODROME = true,
        DISTRICT_PRESERVE = true
    };

    local existingSpecialtyCount = 0;
    local builtDistrictsList = {};
    local seenBuilt = {};
    for dTypeName, pPlot in pairs(existingCityDistricts) do
        local baseType = GetBaseDistrictType(dTypeName);
        if not seenBuilt[baseType] then
            seenBuilt[baseType] = true;
            local dInfo = GameInfo.Districts[dTypeName];
            if dInfo ~= nil then
                local bIsSpec = false;
                if dInfo.RequiresPopulation == true or dInfo.RequiresPopulation == 1 or specialtyBaseTypes[baseType] then
                    bIsSpec = true;
                    existingSpecialtyCount = existingSpecialtyCount + 1;
                end
                table.insert(builtDistrictsList, {
                    DistrictType = dTypeName,
                    BaseDistrictType = baseType,
                    BaseName = Locale.Lookup(dInfo.Name),
                    Plot = pPlot,
                    IconName = "ICON_" .. dTypeName,
                    IsSpecialty = bIsSpec
                });
            end
        end
    end

    print(string.format("DMT Smart Planner: City [%s] already has %d constructed/pinned districts (%d specialty)", cityName, #builtDistrictsList, existingSpecialtyCount));

    local plannedDistricts = {};
    local assignedPlots = {};
    local effectiveCampusPlot = GetExistingDistrictPlot("DISTRICT_CAMPUS");

    local function IsPlotAvailable(plot, isWaterCheck)
        if plot == nil or occupiedPlots[plot:GetIndex()] or assignedPlots[plot:GetIndex()] then
            return false;
        end
        -- Korea rule: No district may touch Seowon (to avoid -1 Science penalty)
        if isKorea and effectiveCampusPlot ~= nil then
            if Map.GetPlotDistance(plot:GetX(), plot:GetY(), effectiveCampusPlot:GetX(), effectiveCampusPlot:GetY()) <= 1 then
                return false;
            end
        end
        -- Vietnam rule: Land specialty districts must be on Woods, Rainforest, or Marsh
        if isVietnam and not isWaterCheck and not IsValidVietnamFeature(plot) then
            return false;
        end
        return true;
    end

    -- Step A1: Dam (Non-specialty) - River Floodplains only, NO Coastal Floodplains, 1 Dam per river system!
    local bestDam = nil;
    if not CityHasDistrict("DISTRICT_DAM") and GameInfo.Districts[distDam] ~= nil then
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidRiverFloodplainForDam(plot) and not IsDamAlreadyOnRiver(playerID, px, py) and IsValidDamPosition(playerID, px, py) then
                    bestDam = plot;
                    break;
                end
            end
        end
    end
    local effectiveDamPlot = bestDam or GetExistingDistrictPlot("DISTRICT_DAM");

    -- Step A2: Aqueduct / River Bridge (Non-specialty)
    -- Rule: Must be adjacent to City Center. Only mark if needed for fresh water boost or Industrial Zone +2 synergy!
    local bestAqueduct = nil;
    local aqueductYieldBonus = "+2 Housing & Water";
    if not CityHasDistrict("DISTRICT_AQUEDUCT") and GameInfo.Districts[distAqueduct] ~= nil then
        local validAqueductPlots = {};
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidAqueductPosition(playerID, px, py) then
                    table.insert(validAqueductPlots, plot);
                end
            end
        end

        if #validAqueductPlots > 0 then
            if not cityHasFreshWater then
                -- Case 1: City has NO fresh water -> Desperately needs Aqueduct (+3 to +4 Housing boost)
                local bestScore = -1;
                for _, plot in ipairs(validAqueductPlots) do
                    local px, py = plot:GetX(), plot:GetY();
                    local score = 10;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if effectiveDamPlot and adj:GetIndex() == effectiveDamPlot:GetIndex() then
                            score = score + 8;
                        elseif IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                            score = score + 3;
                        end
                    end
                    -- Penalize stealing prime Mountain tiles that Campus needs for +3/+4
                    local mCount = 0;
                    for _, adj in pairs(adjPlots) do
                        if adj:IsMountain() then mCount = mCount + 1; end
                    end
                    if mCount >= 2 then score = score - 6; end

                    if score > bestScore then
                        bestScore = score;
                        bestAqueduct = plot;
                    end
                end
                aqueductYieldBonus = "+4 Housing (น้ำจืด)";

            elseif isRome then
                -- Case 2: Rome's Bath -> Always high value (+1 Amenity, +2 Housing, half cost)
                local bestScore = -1;
                for _, plot in ipairs(validAqueductPlots) do
                    local score = 10;
                    local adjPlots = Map.GetAdjacentPlots(plot:GetX(), plot:GetY());
                    for _, adj in pairs(adjPlots) do
                        if effectiveDamPlot and adj:GetIndex() == effectiveDamPlot:GetIndex() then
                            score = score + 8;
                        elseif IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                            score = score + 3;
                        end
                    end
                    if score > bestScore then
                        bestScore = score;
                        bestAqueduct = plot;
                    end
                end
                aqueductYieldBonus = "+2 Housing, +1 Amenity";

            else
                -- Case 3: City ALREADY has fresh water -> ONLY build Aqueduct if it boosts Industrial Zone!
                local bestPairScore = -1;
                local bestPairAQ = nil;

                for _, aqPlot in ipairs(validAqueductPlots) do
                    local aqIndex = aqPlot:GetIndex();
                    local adjPlots = Map.GetAdjacentPlots(aqPlot:GetX(), aqPlot:GetY());
                    for _, izCandidate in pairs(adjPlots) do
                        local izIndex = izCandidate:GetIndex();
                        if izIndex ~= aqIndex and IsPlotAvailable(izCandidate, false) and not izCandidate:IsWater() and not izCandidate:IsMountain() then
                            local izX, izY = izCandidate:GetX(), izCandidate:GetY();
                            local distFromCity = Map.GetPlotDistance(cityX, cityY, izX, izY);
                            local bGaulValid = (not isGaul) or (distFromCity >= 2);

                            if bGaulValid then
                                local testIZScore = 2.0; -- +2 from this Aqueduct!
                                local izSurroundings = Map.GetAdjacentPlots(izX, izY);
                                for _, sPlot in pairs(izSurroundings) do
                                    local sIdx = sPlot:GetIndex();
                                    if effectiveDamPlot and sIdx == effectiveDamPlot:GetIndex() then
                                        testIZScore = testIZScore + 2.0; -- +2 from Dam!
                                    end
                                    local rIdx = sPlot:GetResourceType();
                                    if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                                        testIZScore = testIZScore + 1.0;
                                    end
                                    local tIdx = sPlot:GetTerrainType();
                                    if tIdx ~= -1 and GameInfo.Terrains[tIdx] and GameInfo.Terrains[tIdx].Hills then
                                        testIZScore = testIZScore + 0.5;
                                    end
                                    if (sPlot:IsCity() and sPlot:GetX() == cityX and sPlot:GetY() == cityY) or assignedPlots[sIdx] then
                                        testIZScore = testIZScore + 0.5;
                                    end
                                end

                                -- Check if aqPlot is on a high-mountain tile that Campus wants
                                local aqMountainCount = 0;
                                for _, mAdj in pairs(Map.GetAdjacentPlots(aqPlot:GetX(), aqPlot:GetY())) do
                                    if mAdj:IsMountain() then aqMountainCount = aqMountainCount + 1; end
                                end
                                if aqMountainCount >= 2 then
                                    testIZScore = testIZScore - 1.5;
                                end

                                if testIZScore > bestPairScore then
                                    bestPairScore = testIZScore;
                                    bestPairAQ = aqPlot;
                                end
                            end
                        end
                    end
                end

                -- Only plan Aqueduct if the synergy achieves at least +3 Production for the Industrial Zone!
                if bestPairScore >= 3.0 and bestPairAQ ~= nil then
                    bestAqueduct = bestPairAQ;
                    aqueductYieldBonus = "+2 Housing • บัฟโรงงาน +2";
                else
                    bestAqueduct = nil;
                end
            end
        end

        if bestAqueduct ~= nil then
            assignedPlots[bestAqueduct:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestAqueduct,
                DistrictType = distAqueduct,
                BaseDistrictType = "DISTRICT_AQUEDUCT",
                BaseName = Locale.Lookup(GameInfo.Districts[distAqueduct].Name),
                YieldBonus = aqueductYieldBonus,
                NumericBonus = 2,
                IsSpecialty = false
            });
        end
    end
    local effectiveAqueductPlot = bestAqueduct or GetExistingDistrictPlot("DISTRICT_AQUEDUCT");

    if bestDam ~= nil then
        assignedPlots[bestDam:GetIndex()] = true;
        table.insert(plannedDistricts, {
            Plot = bestDam,
            DistrictType = distDam,
            BaseDistrictType = "DISTRICT_DAM",
            BaseName = Locale.Lookup(GameInfo.Districts[distDam].Name),
            YieldBonus = "+3 Housing & Power",
            NumericBonus = 3,
            IsSpecialty = false
        });
    end

    -- Step C: Canal (Non-specialty)
    local bestCanal = nil;
    if not CityHasDistrict("DISTRICT_CANAL") and GameInfo.Districts[distCanal] ~= nil then
        local bestCanalScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() and not plot:IsHills() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidCanalPosition(playerID, px, py, cityX, cityY) then
                    local pinSub = { X = px, Y = py, Key = distCanal, Type = MAP_PIN_TYPES.DISTRICT };
                    if CanPlacePin(playerID, pinSub) then
                        local cScore = 5;
                        local adjPlots = Map.GetAdjacentPlots(px, py);
                        for _, adj in pairs(adjPlots) do
                            if IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                                cScore = cScore + 2;
                            end
                        end
                        if cScore > bestCanalScore then
                            bestCanalScore = cScore;
                            bestCanal = plot;
                        end
                    end
                end
            end
        end
        if bestCanal ~= nil then
            assignedPlots[bestCanal:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestCanal,
                DistrictType = distCanal,
                BaseDistrictType = "DISTRICT_CANAL",
                BaseName = Locale.Lookup(GameInfo.Districts[distCanal].Name),
                YieldBonus = "+2 [ICON_Production] to IZ",
                NumericBonus = 2,
                IsSpecialty = false
            });
        end
    end
    local effectiveCanalPlot = bestCanal or GetExistingDistrictPlot("DISTRICT_CANAL");

    -- Step D: Industrial Zone (Specialty) - Rule 4: Gaul Oppidum cannot be adjacent to City Center!
    local bestIZ = nil;
    if not CityHasDistrict("DISTRICT_INDUSTRIAL_ZONE") and GameInfo.Districts[distIZ] ~= nil then
        local bestIZScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            local bGaulValid = (not isGaul) or (distFromCity >= 2);

            if bGaulValid and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distIZ, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local izScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if effectiveAqueductPlot and adj:GetIndex() == effectiveAqueductPlot:GetIndex() then
                            izScore = izScore + 2;
                        end
                        if effectiveDamPlot and adj:GetIndex() == effectiveDamPlot:GetIndex() then
                            izScore = izScore + 2;
                        end
                        if effectiveCanalPlot and adj:GetIndex() == effectiveCanalPlot:GetIndex() then
                            izScore = izScore + 2;
                        end
                        local rIdx = adj:GetResourceType();
                        if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                            izScore = izScore + 1;
                        end
                        local tIdx = adj:GetTerrainType();
                        if tIdx ~= -1 and GameInfo.Terrains[tIdx] and GameInfo.Terrains[tIdx].Hills then
                            izScore = izScore + 0.5;
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            izScore = izScore + 0.5;
                        end
                    end
                    if izScore > bestIZScore then
                        bestIZScore = izScore;
                        bestIZ = plot;
                    end
                end
            end
        end
        if bestIZ ~= nil then
            assignedPlots[bestIZ:GetIndex()] = true;
            local izBonus = math.max(1, math.floor(bestIZScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestIZ,
                DistrictType = distIZ,
                BaseDistrictType = "DISTRICT_INDUSTRIAL_ZONE",
                BaseName = Locale.Lookup(GameInfo.Districts[distIZ].Name),
                YieldBonus = "+" .. izBonus .. " [ICON_Production] Prod",
                NumericBonus = izBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveIZPlot = bestIZ or GetExistingDistrictPlot("DISTRICT_INDUSTRIAL_ZONE");

    -- Step E: Harbor (Specialty)
    local bestHarbor = nil;
    if not CityHasDistrict("DISTRICT_HARBOR") and GameInfo.Districts[distHarbor] ~= nil then
        local bestHarborScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, true) and plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distHarbor, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local hScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY then
                            hScore = hScore + 2;
                        end
                        if adj:GetResourceType() ~= -1 then
                            hScore = hScore + 1;
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:GetDistrictType() ~= -1) then
                            hScore = hScore + 0.5;
                        end
                    end
                    if hScore > bestHarborScore then
                        bestHarborScore = hScore;
                        bestHarbor = plot;
                    end
                end
            end
        end
        if bestHarbor ~= nil then
            assignedPlots[bestHarbor:GetIndex()] = true;
            local hBonus = math.max(2, math.floor(bestHarborScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestHarbor,
                DistrictType = distHarbor,
                BaseDistrictType = "DISTRICT_HARBOR",
                BaseName = Locale.Lookup(GameInfo.Districts[distHarbor].Name),
                YieldBonus = "+" .. hBonus .. " [ICON_Gold] Gold",
                NumericBonus = hBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveHarborPlot = bestHarbor or GetExistingDistrictPlot("DISTRICT_HARBOR");

    -- Step F: Commercial Hub (Specialty)
    local bestCommHub = nil;
    if not CityHasDistrict("DISTRICT_COMMERCIAL_HUB") and GameInfo.Districts[distCommHub] ~= nil then
        local bestCHScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCommHub, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local chScore = 0;
                    if plot:IsRiver() then chScore = chScore + 2; end
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if effectiveHarborPlot and adj:GetIndex() == effectiveHarborPlot:GetIndex() then
                            chScore = chScore + 2;
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            chScore = chScore + 0.5;
                        end
                    end
                    if chScore > bestCHScore then
                        bestCHScore = chScore;
                        bestCommHub = plot;
                    end
                end
            end
        end
        if bestCommHub ~= nil then
            assignedPlots[bestCommHub:GetIndex()] = true;
            local chBonus = math.max(2, math.floor(bestCHScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestCommHub,
                DistrictType = distCommHub,
                BaseDistrictType = "DISTRICT_COMMERCIAL_HUB",
                BaseName = Locale.Lookup(GameInfo.Districts[distCommHub].Name),
                YieldBonus = "+" .. chBonus .. " [ICON_Gold] Gold",
                NumericBonus = chBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveCommHubPlot = bestCommHub or GetExistingDistrictPlot("DISTRICT_COMMERCIAL_HUB");

    -- Step G: Campus (Specialty) - Rule 4: Korea Seowon on Hills & isolated from districts!
    local bestCampus = nil;
    if not CityHasDistrict("DISTRICT_CAMPUS") and GameInfo.Districts[distCampus] ~= nil then
        local bestCampusScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distCampus, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    if isKorea then
                        -- Seowon: must be on Hills and NOT adjacent to City Center or other districts
                        if plot:IsHills() and Map.GetPlotDistance(cityX, cityY, px, py) >= 2 then
                            local touchesDistrict = false;
                            local adjPlots = Map.GetAdjacentPlots(px, py);
                            for _, adj in pairs(adjPlots) do
                                if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                    touchesDistrict = true;
                                    break;
                                end
                            end
                            if not touchesDistrict then
                                local cScore = 4; -- Base Seowon +4 Science
                                if cScore > bestCampusScore then
                                    bestCampusScore = cScore;
                                    bestCampus = plot;
                                end
                            end
                        end
                    else
                        local cScore = 0;
                        local adjPlots = Map.GetAdjacentPlots(px, py);
                        for _, adj in pairs(adjPlots) do
                            if adj:IsMountain() then cScore = cScore + 1; end
                            local feat = adj:GetFeatureType();
                            if feat ~= -1 and GameInfo.Features[feat] then
                                local fType = GameInfo.Features[feat].FeatureType;
                                if fType == "FEATURE_GEOTHERMAL_FISSURE" or fType == "FEATURE_REEF" then
                                    cScore = cScore + 2;
                                elseif fType == "FEATURE_JUNGLE" then
                                    cScore = cScore + 0.5;
                                end
                            end
                            if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                cScore = cScore + 0.5;
                            end
                        end
                        if cScore > bestCampusScore then
                            bestCampusScore = cScore;
                            bestCampus = plot;
                        end
                    end
                end
            end
        end
        if bestCampus ~= nil then
            assignedPlots[bestCampus:GetIndex()] = true;
            local cBonus = math.max(1, math.floor(bestCampusScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestCampus,
                DistrictType = distCampus,
                BaseDistrictType = "DISTRICT_CAMPUS",
                BaseName = Locale.Lookup(GameInfo.Districts[distCampus].Name),
                YieldBonus = "+" .. cBonus .. " [ICON_Science] Sci",
                NumericBonus = cBonus,
                IsSpecialty = true
            });
        end
    end
    effectiveCampusPlot = bestCampus or GetExistingDistrictPlot("DISTRICT_CAMPUS");

    -- Step H: Holy Site (Specialty)
    local bestHolySite = nil;
    if not CityHasDistrict("DISTRICT_HOLY_SITE") and GameInfo.Districts[distHolySite] ~= nil then
        local bestHSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distHolySite, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local hsScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if adj:IsMountain() then hsScore = hsScore + 1; end
                        local feat = adj:GetFeatureType();
                        if feat ~= -1 and GameInfo.Features[feat] then
                            if GameInfo.Features[feat].NaturalWonder then
                                hsScore = hsScore + 2;
                            elseif GameInfo.Features[feat].FeatureType == "FEATURE_FOREST" then
                                hsScore = hsScore + 0.5;
                            end
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            hsScore = hsScore + 0.5;
                        end
                    end
                    if hsScore > bestHSScore then
                        bestHSScore = hsScore;
                        bestHolySite = plot;
                    end
                end
            end
        end
        if bestHolySite ~= nil then
            assignedPlots[bestHolySite:GetIndex()] = true;
            local hsBonus = math.max(1, math.floor(bestHSScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestHolySite,
                DistrictType = distHolySite,
                BaseDistrictType = "DISTRICT_HOLY_SITE",
                BaseName = Locale.Lookup(GameInfo.Districts[distHolySite].Name),
                YieldBonus = "+" .. hsBonus .. " [ICON_Faith] Faith",
                NumericBonus = hsBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveHolySitePlot = bestHolySite or GetExistingDistrictPlot("DISTRICT_HOLY_SITE");

    -- Step I: Entertainment Complex (Specialty)
    local bestEntertainment = nil;
    if not CityHasDistrict("DISTRICT_ENTERTAINMENT_COMPLEX") and GameInfo.Districts[distEntertainment] ~= nil then
        local bestECScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distEntertainment, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local ecScore = 1;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                            ecScore = ecScore + 2; -- Potential Theater Square neighbor
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            ecScore = ecScore + 0.5;
                        end
                    end
                    if ecScore > bestECScore then
                        bestECScore = ecScore;
                        bestEntertainment = plot;
                    end
                end
            end
        end
        if bestEntertainment ~= nil then
            assignedPlots[bestEntertainment:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestEntertainment,
                DistrictType = distEntertainment,
                BaseDistrictType = "DISTRICT_ENTERTAINMENT_COMPLEX",
                BaseName = Locale.Lookup(GameInfo.Districts[distEntertainment].Name),
                YieldBonus = "+1 Amenity & +2 [ICON_Culture] TS",
                NumericBonus = 2,
                IsSpecialty = true
            });
        end
    end
    local effectiveEntertainmentPlot = bestEntertainment or GetExistingDistrictPlot("DISTRICT_ENTERTAINMENT_COMPLEX");

    -- Step J: Theater Square (Specialty)
    local bestTheater = nil;
    if not CityHasDistrict("DISTRICT_THEATER") and GameInfo.Districts[distTheater] ~= nil then
        local bestTSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distTheater, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local tsScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if effectiveEntertainmentPlot and adj:GetIndex() == effectiveEntertainmentPlot:GetIndex() then
                            tsScore = tsScore + 2; -- Major adjacency from Entertainment Complex
                        end
                        local feat = adj:GetFeatureType();
                        if feat ~= -1 and GameInfo.Features[feat] and GameInfo.Features[feat].NaturalWonder then
                            tsScore = tsScore + 2;
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            tsScore = tsScore + 0.5;
                        end
                    end
                    if tsScore > bestTSScore then
                        bestTSScore = tsScore;
                        bestTheater = plot;
                    end
                end
            end
        end
        if bestTheater ~= nil then
            assignedPlots[bestTheater:GetIndex()] = true;
            local tsBonus = math.max(1, math.floor(bestTSScore + 0.5));
            table.insert(plannedDistricts, {
                Plot = bestTheater,
                DistrictType = distTheater,
                BaseDistrictType = "DISTRICT_THEATER",
                BaseName = Locale.Lookup(GameInfo.Districts[distTheater].Name),
                YieldBonus = "+" .. tsBonus .. " [ICON_Culture] Cul",
                NumericBonus = tsBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveTheaterPlot = bestTheater or GetExistingDistrictPlot("DISTRICT_THEATER");

    -- Step K: Government Plaza (Non-specialty, 1 per empire, free of Pop cap)
    local bestGov = nil;
    if not CityHasDistrict("DISTRICT_GOVERNMENT") and not HasEmpireGovernmentPlaza(playerID) and not IsEmpireDistrictAlreadyPlanned("DISTRICT_GOVERNMENT") and GameInfo.Districts[distGovPlaza] ~= nil then
        local bestGovScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distGovPlaza, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local gScore = 1;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            gScore = gScore + 1;
                        end
                    end
                    if isCapital then gScore = gScore + 2; end
                    if gScore > bestGovScore then
                        bestGovScore = gScore;
                        bestGov = plot;
                    end
                end
            end
        end
        if bestGov ~= nil then
            assignedPlots[bestGov:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestGov,
                DistrictType = distGovPlaza,
                BaseDistrictType = "DISTRICT_GOVERNMENT",
                BaseName = Locale.Lookup(GameInfo.Districts[distGovPlaza].Name),
                YieldBonus = "+" .. bestGovScore .. " All Adj & Loyalty",
                NumericBonus = bestGovScore,
                IsSpecialty = false
            });
        end
    end
    local effectiveGovPlazaPlot = bestGov or GetExistingDistrictPlot("DISTRICT_GOVERNMENT");

    -- Step L: Diplomatic Quarter (Non-specialty, 1 per empire, free of Pop cap)
    local bestDiplo = nil;
    if not CityHasDistrict("DISTRICT_DIPLOMATIC_QUARTER") and not HasEmpireDiplomaticQuarter(playerID) and not IsEmpireDistrictAlreadyPlanned("DISTRICT_DIPLOMATIC_QUARTER") and GameInfo.Districts[distDiploQuarter] ~= nil then
        local bestDiploScore = 0;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distDiploQuarter, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local dScore = 1;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                            dScore = dScore + 0.5;
                        end
                    end
                    if dScore > bestDiploScore then
                        bestDiploScore = dScore;
                        bestDiplo = plot;
                    end
                end
            end
        end
        if bestDiplo ~= nil then
            assignedPlots[bestDiplo:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestDiplo,
                DistrictType = distDiploQuarter,
                BaseDistrictType = "DISTRICT_DIPLOMATIC_QUARTER",
                BaseName = Locale.Lookup(GameInfo.Districts[distDiploQuarter].Name),
                YieldBonus = "+1 Envoy & +Adj",
                NumericBonus = 1,
                IsSpecialty = false
            });
        end
    end
    local effectiveDiploQuarterPlot = bestDiplo or GetExistingDistrictPlot("DISTRICT_DIPLOMATIC_QUARTER");

    -- Step M: Encampment (Specialty) - Rule 3 & 4: dist >= 2 and dist <= 3
    local bestEncampment = nil;
    if not CityHasDistrict("DISTRICT_ENCAMPMENT") and GameInfo.Districts[distEncampment] ~= nil then
        local bestEncScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            if distFromCity >= 2 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distEncampment, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local encScore = 2;
                    if plot:IsHills() then encScore = encScore + 4; end -- High defense on hills
                    if distFromCity == 3 then encScore = encScore + 2; end -- Outer perimeter defense
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        local rIdx = adj:GetResourceType();
                        if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                            encScore = encScore + 1;
                        end
                    end
                    if encScore > bestEncScore then
                        bestEncScore = encScore;
                        bestEncampment = plot;
                    end
                end
            end
        end
        if bestEncampment ~= nil then
            assignedPlots[bestEncampment:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestEncampment,
                DistrictType = distEncampment,
                BaseDistrictType = "DISTRICT_ENCAMPMENT",
                BaseName = Locale.Lookup(GameInfo.Districts[distEncampment].Name),
                YieldBonus = "+2 [ICON_Production] & Defense",
                NumericBonus = 2,
                IsSpecialty = true
            });
        end
    end
    local effectiveEncampmentPlot = bestEncampment or GetExistingDistrictPlot("DISTRICT_ENCAMPMENT");

    -- Step N: Neighborhood (Non-specialty) - Rule 4: Kongo Mbanza on Woods/Rainforest, ignores Appeal!
    local bestNeighborhood = nil;
    if not CityHasDistrict("DISTRICT_NEIGHBORHOOD") and GameInfo.Districts[distNeighborhood] ~= nil then
        local bestNScore = -999;
        local bestAppeal = 0;
        local bestHousing = 4;
        local bIsMbanza = (isKongo or distNeighborhood == "DISTRICT_MBANZA");

        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distNeighborhood, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    if bIsMbanza then
                        -- Kongo: Mbanza requires Woods or Rainforest, ignores Appeal
                        local fIdx = plot:GetFeatureType();
                        if fIdx ~= -1 and GameInfo.Features[fIdx] ~= nil then
                            local fType = GameInfo.Features[fIdx].FeatureType;
                            if fType == "FEATURE_FOREST" or fType == "FEATURE_JUNGLE" then
                                bestNeighborhood = plot;
                                bestHousing = 5;
                                break;
                            end
                        end
                    else
                        local appeal = plot:GetAppeal();
                        local housing = 4;
                        if appeal >= 4 then housing = 6;
                        elseif appeal >= 2 then housing = 5;
                        elseif appeal >= -1 then housing = 4;
                        else housing = 3; end

                        local nScore = (appeal * 3) + housing;
                        if nScore > bestNScore then
                            bestNScore = nScore;
                            bestAppeal = appeal;
                            bestHousing = housing;
                            bestNeighborhood = plot;
                        end
                    end
                end
            end
        end
        if bestNeighborhood ~= nil then
            assignedPlots[bestNeighborhood:GetIndex()] = true;
            local yieldText = bIsMbanza and "+5 Housing & Food/Gold" or string.format("+%d Housing (Appeal %d)", bestHousing, bestAppeal);
            table.insert(plannedDistricts, {
                Plot = bestNeighborhood,
                DistrictType = distNeighborhood,
                BaseDistrictType = "DISTRICT_NEIGHBORHOOD",
                BaseName = Locale.Lookup(GameInfo.Districts[distNeighborhood].Name),
                YieldBonus = yieldText,
                NumericBonus = bestHousing,
                IsSpecialty = false
            });
        end
    end
    local effectiveNeighborhoodPlot = bestNeighborhood or GetExistingDistrictPlot("DISTRICT_NEIGHBORHOOD");

    -- Step O: Aerodrome (Specialty, flat land only, consumes Pop slot)
    local bestAerodrome = nil;
    if not CityHasDistrict("DISTRICT_AERODROME") and GameInfo.Districts[distAerodrome] ~= nil then
        local bestAeroScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            if distFromCity >= 2 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() and not plot:IsHills() then
                local pinSub = { X = px, Y = py, Key = distAerodrome, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local aeroScore = (distFromCity == 3) and 6 or 4;
                    if aeroScore > bestAeroScore then
                        bestAeroScore = aeroScore;
                        bestAerodrome = plot;
                    end
                end
            end
        end
        if bestAerodrome ~= nil then
            assignedPlots[bestAerodrome:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestAerodrome,
                DistrictType = distAerodrome,
                BaseDistrictType = "DISTRICT_AERODROME",
                BaseName = Locale.Lookup(GameInfo.Districts[distAerodrome].Name),
                YieldBonus = "+4 Air Slots & [ICON_Production] Air",
                NumericBonus = 4,
                IsSpecialty = true
            });
        end
    end
    local effectiveAerodromePlot = bestAerodrome or GetExistingDistrictPlot("DISTRICT_AERODROME");

    -- Step P: Spaceport (Non-specialty, flat land only)
    local bestSpaceport = nil;
    if not CityHasDistrict("DISTRICT_SPACEPORT") and GameInfo.Districts[distSpaceport] ~= nil then
        local bestSpaceScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            if distFromCity >= 2 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() and not plot:IsHills() then
                local pinSub = { X = px, Y = py, Key = distSpaceport, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local spaceScore = (distFromCity == 3) and 6 or 4;
                    if spaceScore > bestSpaceScore then
                        bestSpaceScore = spaceScore;
                        bestSpaceport = plot;
                    end
                end
            end
        end
        if bestSpaceport ~= nil then
            assignedPlots[bestSpaceport:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestSpaceport,
                DistrictType = distSpaceport,
                BaseDistrictType = "DISTRICT_SPACEPORT",
                BaseName = Locale.Lookup(GameInfo.Districts[distSpaceport].Name),
                YieldBonus = "Science Victory Projects",
                NumericBonus = 5,
                IsSpecialty = false
            });
        end
    end
    local effectiveSpaceportPlot = bestSpaceport or GetExistingDistrictPlot("DISTRICT_SPACEPORT");

    -- Rule 5: Priority Ranking & Population Cap Assignment
    for _, item in ipairs(plannedDistricts) do
        item.PriorityScore = CalculateDistrictPriority(item, cityHasFreshWater);
    end

    table.sort(plannedDistricts, function(a, b)
        return a.PriorityScore > b.PriorityScore;
    end);

    local specialtyCount = existingSpecialtyCount;
    for rank, item in ipairs(plannedDistricts) do
        item.Rank = rank;
        if item.IsSpecialty then
            specialtyCount = specialtyCount + 1;
            local reqPop = 1 + (specialtyCount - 1) * 3;
            if isGermany then
                reqPop = (specialtyCount == 1) and 1 or (1 + (specialtyCount - 2) * 3);
            end
            item.PopReq = reqPop;
            item.PopReqText = "Pop " .. reqPop;
        else
            item.PopReq = 0;
            item.PopReqText = "ไม่กิน Pop";
        end
    end

    -- Populate HUD UI Panel & Place World Map Pins
    if m_DistrictIM ~= nil then
        m_DistrictIM:ResetInstances();
    end

    local pinsToUpdate = {};
    for _, item in ipairs(plannedDistricts) do
        local px, py = item.Plot:GetX(), item.Plot:GetY();
        -- Format: [CityName] #Rank DistrictName (YieldBonus)
        local pinName = string.format("[%s] #%d %s (%s)", cityName, item.Rank, item.BaseName, item.YieldBonus);
        local iconName = "ICON_" .. item.DistrictType;

        -- 1. Populate HUD UI list
        if m_DistrictIM ~= nil then
            local uiEntry = m_DistrictIM:GetInstance();
            uiEntry.DistrictIcon:SetIcon(iconName);
            uiEntry.DistrictNameLabel:SetText(string.format("#%d %s", item.Rank, item.BaseName));
            uiEntry.DistrictBonusLabel:SetText(string.format("%s • %s", item.YieldBonus, item.PopReqText));
        end

        -- 2. Place Map Pin on World Map
        if not HasManualPinAtPlot(playerCfg, px, py) then
            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                pin:SetName(pinName);
                pin:SetIconName(iconName);
                pin:SetVisibility(playerID);

                m_AutoDistrictPins[px .. "_" .. py] = {
                    CityID = cityID,
                    CityName = cityName,
                    IsCapital = isCapital,
                    CityX = cityX,
                    CityY = cityY,
                    PlotX = px,
                    PlotY = py,
                    DistrictType = item.DistrictType,
                    BaseDistrictType = item.BaseDistrictType,
                    BaseName = item.BaseName,
                    YieldBonus = item.YieldBonus,
                    Priority = item.Rank,
                    IsSpecialty = item.IsSpecialty,
                    PopReq = item.PopReq
                };

                local pinSubject = CreateMapPinSubject(pin);
                table.insert(pinsToUpdate, pinSubject);
            end
        end
    end

    -- Also list already constructed districts in the HUD UI panel
    if m_DistrictIM ~= nil and #builtDistrictsList > 0 then
        for _, builtItem in ipairs(builtDistrictsList) do
            local uiEntry = m_DistrictIM:GetInstance();
            uiEntry.DistrictIcon:SetIcon(builtItem.IconName);
            uiEntry.DistrictNameLabel:SetText(string.format("%s [เสร็จ]", builtItem.BaseName));
            local plotCoords = (builtItem.Plot ~= nil) and string.format("(%d, %d)", builtItem.Plot:GetX(), builtItem.Plot:GetY()) or "ในเมือง";
            local specText = builtItem.IsSpecialty and "นับ Pop" or "ไม่กิน Pop";
            uiEntry.DistrictBonusLabel:SetText(string.format("%s • %s", plotCoords, specText));
        end
    end

    if Controls.DistrictListStack then
        Controls.DistrictListStack:CalculateSize();
    end
    if Controls.DistrictScrollPanel then
        Controls.DistrictScrollPanel:CalculateSize();
    end

    Network.BroadcastPlayerInfo();
    LuaEvents.DMT_RefreshMapPins();

    for _, pinSubject in ipairs(pinsToUpdate) do
        LuaEvents.DMT_MapPinAdded(playerCfg:GetMapPin(pinSubject.X, pinSubject.Y));
    end
    if #pinsToUpdate > 0 then
        if LuaEvents.DMT_UpdatePinYields then
            LuaEvents.DMT_UpdatePinYields(playerID, pinsToUpdate);
        elseif UpdatePinYields then
            UpdatePinYields(playerID, pinsToUpdate);
        end
    end

    -- Show City District HUD Panel
    if Controls.CityDistrictPlanPanel then
        Controls.CityDistrictPlanPanel:SetHide(false);
        if Controls.CityNameLabel then
            if #plannedDistricts > 0 and #builtDistrictsList > 0 then
                Controls.CityNameLabel:SetText(string.format("ผังเขต [%s] (สร้างแล้ว %d • รอสร้าง %d):", cityName, #builtDistrictsList, #plannedDistricts));
            elseif #plannedDistricts == 0 and #builtDistrictsList > 0 then
                Controls.CityNameLabel:SetText(string.format("ผังเขต [%s] (สร้างครบแล้ว %d เขต):", cityName, #builtDistrictsList));
            else
                Controls.CityNameLabel:SetText(string.format("ผังเขต [%s] (ลำดับสร้าง %d เขต):", cityName, #plannedDistricts));
            end
        end
        if Controls.LookAtCityButton then
            Controls.LookAtCityButton:RegisterCallback(Mouse.eLClick, function()
                UI.LookAtPlot(cityX, cityY);
            end);
        end
    end

    UI.PlaySound("Map_Pin_Add");
    print(string.format("DMT Smart Planner: Successfully displayed UI and placed %d district pins for [%s] with priorities!", #plannedDistricts, cityName));
end

-- =======================================================================
-- Turn-by-Turn Dynamic Validation & Auto Refresh
-- =======================================================================

function ValidateAndRefreshAutoPins(playerID)
    if playerID == nil or playerID ~= Game.GetLocalPlayer() then
        playerID = Game.GetLocalPlayer();
    end
    if playerID == -1 or playerID == 1000 then return; end

    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local allPins = playerCfg:GetMapPins();
    if allPins == nil then return; end

    local hasRemovedPins = false;
    local replanCities = {}; -- map of cityKey -> { CityX, CityY, CityName }
    local pinsToRemove = {};

    for _, pin in pairs(allPins) do
        if pin ~= nil then
            local px, py = pin:GetHexX(), pin:GetHexY();
            local key = px .. "_" .. py;
            local pinName = pin:GetName() or "";

            local autoInfo = m_AutoDistrictPins[key];
            local isDistrictPin = (autoInfo ~= nil) or pinName:match("^%[.-%]%s*#%d") or pinName:match("^%[เมือง");

            if isDistrictPin then
                local plot = Map.GetPlot(px, py);
                local bShouldRemove = false;
                local reason = "";

                if plot == nil then
                    bShouldRemove = true;
                    reason = "Nil plot";
                elseif plot:IsOwned() and plot:GetOwner() ~= playerID then
                    bShouldRemove = true;
                    reason = "Border taken by foreign civ";
                elseif plot:GetDistrictType() ~= -1 or plot:IsCity() then
                    bShouldRemove = true;
                    reason = "District or city already constructed";
                end

                local targetCityX = autoInfo and autoInfo.CityX or nil;
                local targetCityY = autoInfo and autoInfo.CityY or nil;

                if targetCityX == nil or targetCityY == nil then
                    local cName = pinName:match("^%[(.-)%]%s*#%d") or pinName:match("^%[[^:]+:%s*(.-)%]");
                    local pPlayer = Players[playerID];
                    if pPlayer and pPlayer:GetCities() then
                        for i, c in pPlayer:GetCities():Members() do
                            if cName and Locale.Lookup(c:GetName()) == cName then
                                targetCityX = c:GetX();
                                targetCityY = c:GetY();
                                break;
                            end
                        end
                    end
                end

                if targetCityX and targetCityY then
                    local pCity = CityManager.GetCityAt(targetCityX, targetCityY);
                    if pCity == nil or pCity:GetOwner() ~= playerID then
                        bShouldRemove = true;
                        reason = "City lost or razed";
                    end
                end

                if bShouldRemove then
                    table.insert(pinsToRemove, {
                        ID = pin:GetID(),
                        Pin = pin,
                        Key = key,
                        Reason = reason,
                        TargetCityX = targetCityX,
                        TargetCityY = targetCityY,
                        Px = px,
                        Py = py,
                        PinName = pinName
                    });
                else
                    if m_AutoDistrictPins[key] == nil and targetCityX and targetCityY then
                        m_AutoDistrictPins[key] = {
                            CityX = targetCityX,
                            CityY = targetCityY,
                            PlotX = px,
                            PlotY = py,
                            PinName = pinName
                        };
                    end
                end
            end
        end
    end

    local deletedIDs = {};
    for _, item in ipairs(pinsToRemove) do
        print(string.format("DMT Turn Check: Removing invalid district pin at (%d, %d) [%s] - Reason: %s", item.Px, item.Py, item.PinName, item.Reason));
        if item.ID ~= nil and not deletedIDs[item.ID] then
            deletedIDs[item.ID] = true;
            pcall(function() LuaEvents.DMT_MapPinRemoved(item.Pin); end);
            pcall(function() playerCfg:DeleteMapPin(item.ID); end);
            m_AutoDistrictPins[item.Key] = nil;
            hasRemovedPins = true;
        end

        if item.Reason == "Border taken by foreign civ" and item.TargetCityX and item.TargetCityY then
            local cKey = item.TargetCityX .. "_" .. item.TargetCityY;
            replanCities[cKey] = { CityX = item.TargetCityX, CityY = item.TargetCityY };
        end
    end

    if hasRemovedPins then
        Network.BroadcastPlayerInfo();
        LuaEvents.DMT_RefreshMapPins();
    end

    for _, cityInfo in pairs(replanCities) do
        print(string.format("DMT Turn Check: Automatically re-planning districts for city at (%d, %d)", cityInfo.CityX, cityInfo.CityY));
        OptimizeCityDistricts(playerID, cityInfo.CityX, cityInfo.CityY, nil, true);
    end
end

function DMT_OnLocalPlayerTurnBegin()
    local playerID = Game.GetLocalPlayer();
    if playerID == -1 or playerID == 1000 then return; end
    ValidateAndRefreshAutoPins(playerID);
end

function DMT_OnPlayerTurnActivated(playerID, bIsFirstTime)
    if playerID ~= Game.GetLocalPlayer() then return; end
    ValidateAndRefreshAutoPins(playerID);
end

-- =======================================================================
-- Hotkey Handler (SHIFT + A)
-- =======================================================================
local m_LastHotkeyTriggerTime = 0;
function OnTriggerSmartPlannerHotkey()
    local now = os.clock();
    if (now - m_LastHotkeyTriggerTime) < 0.5 then
        return;
    end
    m_LastHotkeyTriggerTime = now;

    local playerID = Game.GetLocalPlayer();
    if playerID == -1 or playerID == 1000 then return; end
    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    print("DMT Hotkey: SHIFT+A pressed. Analyzing selection and context...");
    m_SettlerPanelDismissedByUser = false;

    -- 1. Check if a unit is currently selected
    local pSelectedUnit = UI.GetHeadSelectedUnit();
    if pSelectedUnit ~= nil then
        local unitInfo = GameInfo.Units[pSelectedUnit:GetUnitType()];
        if unitInfo and (unitInfo.FoundCity == true or unitInfo.FoundCity == 1) then
            print("DMT Hotkey: Triggering Settler Recommendation for selected Settler");
            RecommendSettlerSpots(playerID, pSelectedUnit, true);
            return;
        end
    end

    -- 2. Check if a city is currently selected
    local pSelectedCity = UI.GetHeadSelectedCity();
    if pSelectedCity ~= nil then
        print("DMT Hotkey: Triggering District Optimization for selected City");
        OptimizeCityDistricts(playerID, pSelectedCity:GetX(), pSelectedCity:GetY(), pSelectedCity:GetID(), true);
        return;
    end

    -- 3. Check cursor plot
    local cursorX, cursorY = UI.GetCursorPlotCoord();
    local cursorPlot = Map.GetPlot(cursorX, cursorY);
    if cursorPlot ~= nil then
        if cursorPlot:IsCity() then
            print("DMT Hotkey: Triggering District Optimization for city under cursor");
            local cityUnderCursor = CityManager.GetCityAt(cursorX, cursorY);
            local cId = cityUnderCursor and cityUnderCursor:GetID() or -1;
            OptimizeCityDistricts(playerID, cursorX, cursorY, cId, true);
            return;
        end
        local owningCity = (Cities and Cities.GetPlotPurchaseCity) and Cities.GetPlotPurchaseCity(cursorPlot) or nil;
        if owningCity ~= nil and owningCity:GetOwner() == playerID then
            print("DMT Hotkey: Triggering District Optimization for owning city: " .. Locale.Lookup(owningCity:GetName()));
            UI.SelectCity(owningCity);
            OptimizeCityDistricts(playerID, owningCity:GetX(), owningCity:GetY(), owningCity:GetID(), true);
            return;
        end
        local cityAt = CityManager.GetCityAt(cursorX, cursorY);
        if cityAt ~= nil and cityAt:GetOwner() == playerID then
            print("DMT Hotkey: Triggering District Optimization for city at cursor plot");
            OptimizeCityDistricts(playerID, cityAt:GetX(), cityAt:GetY(), cityAt:GetID(), true);
            return;
        end
    end

    -- 4. Check if player has any Settler alive
    local pUnits = pPlayer:GetUnits();
    if pUnits ~= nil then
        for i, unit in pUnits:Members() do
            local uInfo = GameInfo.Units[unit:GetUnitType()];
            if uInfo and (uInfo.FoundCity == true or uInfo.FoundCity == 1) then
                print("DMT Hotkey: Found player Settler, selecting and recommending spots");
                UI.SelectUnit(unit);
                UI.LookAtPlot(unit:GetX(), unit:GetY());
                RecommendSettlerSpots(playerID, unit, true);
                return;
            end
        end
    end

    -- 5. Fallback: optimize capital or first city
    local pCities = pPlayer:GetCities();
    if pCities ~= nil then
        local capital = pCities:GetCapitalCity();
        if capital ~= nil then
            print("DMT Hotkey: Fallback to Capital City District Optimization");
            UI.SelectCity(capital);
            UI.LookAtPlot(capital:GetX(), capital:GetY());
            OptimizeCityDistricts(playerID, capital:GetX(), capital:GetY(), capital:GetID(), true);
            return;
        end
        for i, city in pCities:Members() do
            print("DMT Hotkey: Fallback to City District Optimization");
            UI.SelectCity(city);
            UI.LookAtPlot(city:GetX(), city:GetY());
            OptimizeCityDistricts(playerID, city:GetX(), city:GetY(), city:GetID(), true);
            return;
        end
    end

    print("DMT Hotkey: No Settler or City found to plan.");
end

-- =======================================================================
-- Event Handlers
-- =======================================================================

function DMT_OnUnitSelectionChanged(playerID, unitID, hexI, hexJ, hexK, bSelected, bEditable)
    if playerID ~= Game.GetLocalPlayer() then return; end

    if not bSelected then
        m_SettlerPanelDismissedByUser = false;
        if Controls.SettlerRecommendationPanel then
            Controls.SettlerRecommendationPanel:SetHide(true);
        end
        return;
    end

    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    local pUnit = pPlayer:GetUnits():FindID(unitID);
    if not pUnit then return; end

    local unitInfo = GameInfo.Units[pUnit:GetUnitType()];
    if unitInfo and (unitInfo.FoundCity == true or unitInfo.FoundCity == 1) then
        if not m_SettlerPanelDismissedByUser then
            RecommendSettlerSpots(playerID, pUnit);
        end
    else
        m_SettlerPanelDismissedByUser = false;
        if Controls.SettlerRecommendationPanel then
            Controls.SettlerRecommendationPanel:SetHide(true);
        end
    end
end

function DMT_OnUnitMoveComplete(playerID, unitID, x, y)
    if playerID ~= Game.GetLocalPlayer() then return; end

    local pSelectedUnit = UI.GetHeadSelectedUnit();
    if pSelectedUnit ~= nil and pSelectedUnit:GetID() == unitID then
        local unitInfo = GameInfo.Units[pSelectedUnit:GetUnitType()];
        if unitInfo and (unitInfo.FoundCity == true or unitInfo.FoundCity == 1) then
            if not m_SettlerPanelDismissedByUser then
                RecommendSettlerSpots(playerID, pSelectedUnit);
            end
        end
    end
end

function DMT_OnCityAddedToMap(ownerPlayerID, cityID, cityX, cityY)
    if ownerPlayerID ~= Game.GetLocalPlayer() then return; end
    OptimizeCityDistricts(ownerPlayerID, cityX, cityY, cityID, false);
end

function DMT_OnCitySelectionChanged(owner, cityID, i, j, k, bSelected, bEditable)
    if owner ~= Game.GetLocalPlayer() then return; end
    if not bSelected then
        if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
            Controls.CityDistrictPlanPanel:SetHide(true);
        end
    end
end

-- =======================================================================
-- Initialization & Input Handling
-- =======================================================================
local m_SmartPlannerInitialized = false;
local m_IsShiftDownSmartPlanner = false;

function OnSmartPlannerInputHandler(pInputStruct:table)
    local uiMsg = pInputStruct:GetMessageType();
    local key = pInputStruct:GetKey();

    if key == Keys.VK_SHIFT then
        m_IsShiftDownSmartPlanner = (uiMsg == KeyEvents.KeyDown);
    end

    -- Close open panels on ESC key
    if key == Keys.VK_ESCAPE and uiMsg == KeyEvents.KeyUp then
        local bHandled = false;
        if Controls.SettlerRecommendationPanel and not Controls.SettlerRecommendationPanel:IsHidden() then
            OnCloseSettlerPanel();
            bHandled = true;
        end
        if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
            OnCloseDistrictPanel();
            bHandled = true;
        end
        if bHandled then
            return true;
        end
    end

    if (uiMsg == KeyEvents.KeyDown or uiMsg == KeyEvents.KeyUp) then
        local isShift = m_IsShiftDownSmartPlanner or (pInputStruct.IsShiftDown and pInputStruct:IsShiftDown());
        local isKeyA = (key == Keys.A or key == 65 or (Keys.VK_A and key == Keys.VK_A));
        if isShift and isKeyA then
            print("DMT: Shift+A detected in SmartPlanner context, triggering hotkey!");
            m_SettlerPanelDismissedByUser = false;
            OnTriggerSmartPlannerHotkey();
            return true;
        end
    end
    return false;
end

function DMT_SmartPlanner_Initialize()
    if m_SmartPlannerInitialized then return; end
    m_SmartPlannerInitialized = true;

    EnsureInstanceManagers();

    ContextPtr:SetInputHandler(OnSmartPlannerInputHandler, true);

    Events.UnitSelectionChanged.Add(DMT_OnUnitSelectionChanged);
    Events.UnitMoveComplete.Add(DMT_OnUnitMoveComplete);
    Events.CityAddedToMap.Add(DMT_OnCityAddedToMap);
    Events.CitySelectionChanged.Add(DMT_OnCitySelectionChanged);

    if LuaEvents.ProductionPanel_Open then
        LuaEvents.ProductionPanel_Open.Add(function()
            if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
                Controls.CityDistrictPlanPanel:SetHide(true);
            end
        end);
    end
    if LuaEvents.CityPanel_ProductionOpen then
        LuaEvents.CityPanel_ProductionOpen.Add(function()
            if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
                Controls.CityDistrictPlanPanel:SetHide(true);
            end
        end);
    end

    -- Turn-by-Turn Dynamic Border & District Validation
    Events.LocalPlayerTurnBegin.Add(DMT_OnLocalPlayerTurnBegin);
    Events.PlayerTurnActivated.Add(DMT_OnPlayerTurnActivated);
    if Events.LoadGameViewStateDone ~= nil then
        Events.LoadGameViewStateDone.Add(function()
            local pId = Game.GetLocalPlayer();
            if pId ~= -1 and pId ~= 1000 then
                ValidateAndRefreshAutoPins(pId);
            end
        end);
    end

    -- Hotkey Listener for SHIFT + A & Close Panels
    LuaEvents.DMT_TriggerSmartPlannerHotkey.Add(OnTriggerSmartPlannerHotkey);
    LuaEvents.DMT_ClosePanels.Add(function()
        OnCloseSettlerPanel();
        OnCloseDistrictPanel();
    end);

    LuaEvents.DMT_PlanDistrictsForCity.Add(OptimizeCityDistricts);
    LuaEvents.DMT_ClearAutoDistricts.Add(ClearAutoDistrictsForCity);

    print("DMT Smart Planner initialized with HUD UI, SHIFT+A hotkey, 16 districts, and turn-by-turn validation successfully.");
end
