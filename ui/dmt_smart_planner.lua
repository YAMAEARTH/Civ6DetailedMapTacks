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

function UpdateSmartPlannerContextVisibility()
    local bSettlerOpen = Controls.SettlerRecommendationPanel and not Controls.SettlerRecommendationPanel:IsHidden();
    local bDistrictOpen = Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden();
    if bSettlerOpen or bDistrictOpen then
        ContextPtr:SetHide(false);
    else
        ContextPtr:SetHide(true);
    end
end

function OnCloseSettlerPanel()
    m_SettlerPanelDismissedByUser = true;
    if Controls.SettlerRecommendationPanel then
        Controls.SettlerRecommendationPanel:SetHide(true);
    end
    UpdateSmartPlannerContextVisibility();
    UI.PlaySound("Play_UI_Click");
end

function OnCloseDistrictPanel()
    if Controls.CityDistrictPlanPanel then
        Controls.CityDistrictPlanPanel:SetHide(true);
    end
    UpdateSmartPlannerContextVisibility();
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

-- Fast lookup tables for all Civilization & Leader Unique Districts
local KNOWN_UNIQUE_DISTRICTS = {
    CIVILIZATION_GERMANY = { DISTRICT_INDUSTRIAL_ZONE = "DISTRICT_HANSA" },
    CIVILIZATION_GAUL = { DISTRICT_INDUSTRIAL_ZONE = "DISTRICT_OPPIDUM" },
    CIVILIZATION_KOREA = { DISTRICT_CAMPUS = "DISTRICT_SEOWON" },
    CIVILIZATION_MAYA = { DISTRICT_CAMPUS = "DISTRICT_OBSERVATORY" },
    CIVILIZATION_GREECE = { DISTRICT_THEATER = "DISTRICT_ACROPOLIS" },
    CIVILIZATION_MALI = { DISTRICT_COMMERCIAL_HUB = "DISTRICT_SUGUBA" },
    CIVILIZATION_VIETNAM = { DISTRICT_ENCAMPMENT = "DISTRICT_THANH" },
    CIVILIZATION_ROME = { DISTRICT_AQUEDUCT = "DISTRICT_BATH" },
    CIVILIZATION_KONGO = { DISTRICT_NEIGHBORHOOD = "DISTRICT_MBANZA" },
    CIVILIZATION_RUSSIA = { DISTRICT_HOLY_SITE = "DISTRICT_LAVRA" },
    CIVILIZATION_PHOENICIA = { DISTRICT_HARBOR = "DISTRICT_COTHON" },
    CIVILIZATION_ENGLAND = { DISTRICT_HARBOR = "DISTRICT_ROYAL_NAVY_DOCKYARD" },
    CIVILIZATION_BRAZIL = {
        DISTRICT_ENTERTAINMENT_COMPLEX = "DISTRICT_STREET_CARNIVAL",
        DISTRICT_WATER_ENTERTAINMENT_COMPLEX = "DISTRICT_WATER_STREET_CARNIVAL"
    },
    CIVILIZATION_BYZANTIUM = { DISTRICT_ENTERTAINMENT_COMPLEX = "DISTRICT_HIPPODROME" },
    CIVILIZATION_ZULU = { DISTRICT_ENCAMPMENT = "DISTRICT_IKANDA" }
};

local REVERSE_UNIQUE_DISTRICTS = {
    DISTRICT_HANSA = "DISTRICT_INDUSTRIAL_ZONE",
    DISTRICT_OPPIDUM = "DISTRICT_INDUSTRIAL_ZONE",
    DISTRICT_SEOWON = "DISTRICT_CAMPUS",
    DISTRICT_OBSERVATORY = "DISTRICT_CAMPUS",
    DISTRICT_ACROPOLIS = "DISTRICT_THEATER",
    DISTRICT_SUGUBA = "DISTRICT_COMMERCIAL_HUB",
    DISTRICT_SUK_FLOATINGMARKET = "DISTRICT_COMMERCIAL_HUB",
    DISTRICT_THANH = "DISTRICT_ENCAMPMENT",
    DISTRICT_IKANDA = "DISTRICT_ENCAMPMENT",
    DISTRICT_BATH = "DISTRICT_AQUEDUCT",
    DISTRICT_MBANZA = "DISTRICT_NEIGHBORHOOD",
    DISTRICT_HAG_MADAGASCAR_FOKO = "DISTRICT_NEIGHBORHOOD",
    DISTRICT_LAVRA = "DISTRICT_HOLY_SITE",
    DISTRICT_COTHON = "DISTRICT_HARBOR",
    DISTRICT_ROYAL_NAVY_DOCKYARD = "DISTRICT_HARBOR",
    DISTRICT_STREET_CARNIVAL = "DISTRICT_ENTERTAINMENT_COMPLEX",
    DISTRICT_HIPPODROME = "DISTRICT_ENTERTAINMENT_COMPLEX",
    DISTRICT_WATER_STREET_CARNIVAL = "DISTRICT_WATER_ENTERTAINMENT_COMPLEX"
};

-- Get unique district replacement for local player
function GetPlayerUniqueDistrict(playerID, baseDistrictType)
    if not baseDistrictType or not GameInfo.Districts[baseDistrictType] then
        return baseDistrictType;
    end
    local playerConfig = PlayerConfigurations[playerID];
    if not playerConfig then return baseDistrictType; end

    local civType = playerConfig:GetCivilizationTypeName();
    local leaderType = playerConfig:GetLeaderTypeName();

    -- Check known mappings first for rapid zero-overhead lookup
    if civType and KNOWN_UNIQUE_DISTRICTS[civType] and KNOWN_UNIQUE_DISTRICTS[civType][baseDistrictType] then
        local uType = KNOWN_UNIQUE_DISTRICTS[civType][baseDistrictType];
        if GameInfo.Districts[uType] ~= nil then
            return uType;
        end
    end

    if GameInfo.DistrictReplaces ~= nil then
        for row in GameInfo.DistrictReplaces() do
            if row.ReplacesDistrictType == baseDistrictType then
                local uniqueDistrict = GameInfo.Districts[row.CivUniqueDistrictType];
                if uniqueDistrict and uniqueDistrict.TraitType then
                    if GameInfo.CivilizationTraits ~= nil then
                        for civTrait in GameInfo.CivilizationTraits() do
                            if civTrait.CivilizationType == civType and civTrait.TraitType == uniqueDistrict.TraitType then
                                return row.CivUniqueDistrictType;
                            end
                        end
                    end
                    if GameInfo.LeaderTraits ~= nil then
                        for leaderTrait in GameInfo.LeaderTraits() do
                            if leaderTrait.LeaderType == leaderType and leaderTrait.TraitType == uniqueDistrict.TraitType then
                                return row.CivUniqueDistrictType;
                            end
                        end
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
    if REVERSE_UNIQUE_DISTRICTS[districtType] ~= nil then
        return REVERSE_UNIQUE_DISTRICTS[districtType];
    end
    if GameInfo.DistrictReplaces ~= nil then
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

local function CountEmpireSpaceports(playerID)
    local count = 0;
    local pPlayer = Players[playerID];
    if pPlayer and pPlayer:GetCities() then
        for _, city in pPlayer:GetCities():Members() do
            local pCityDistricts = city:GetDistricts();
            if pCityDistricts ~= nil then
                for _, district in pCityDistricts:Members() do
                    if district ~= nil and type(district) == "table" and district.GetType ~= nil then
                        local dType = district:GetType();
                        if dType ~= -1 and GameInfo.Districts[dType] ~= nil and GameInfo.Districts[dType].DistrictType == "DISTRICT_SPACEPORT" then
                            count = count + 1;
                            break;
                        end
                    end
                end
            end
        end
    end
    for key, info in pairs(m_AutoDistrictPins) do
        if type(info) == "table" and (info.BaseDistrictType == "DISTRICT_SPACEPORT" or info.DistrictType == "DISTRICT_SPACEPORT") then
            count = count + 1;
        end
    end
    return count;
end

-- Rule 3: Canal Valid Geometry & Strict Civ 6 Engine Rules
-- 1. Must be on flat land (not water, not hills, not mountain)
-- 2. Must NOT create a three-way junction: in Civ 6, a Canal district is strictly forbidden
--    from touching 3 or more connectable endpoints (water tiles or city center).
--    It must connect EXACTLY 2 endpoints (#connectables == 2).
-- 3. The 2 endpoints must be:
--    - Water + Water (Coast/Lake to Coast/Lake)
--    - Water + THIS City Center (cannot connect 2 cities)
-- 4. No sharp hairpin bend: endpoints cannot be adjacent to each other (Map.GetPlotDistance >= 2)
-- 5. Cannot connect to Rivers (rivers are hex borders, not water plots)
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
            -- In Civ 6 Gathering Storm, districts cannot be placed adjacent to another city's center!
            -- Only THIS city's center is a valid connectable city endpoint.
            local isThisCity = (adj:GetX() == cityX and adj:GetY() == cityY);
            if isWater or isThisCity then
                table.insert(connectables, {
                    Plot = adj,
                    X = adj:GetX(),
                    Y = adj:GetY(),
                    IsWater = isWater,
                    IsCity = isThisCity
                });
            end
        end
    end

    -- Civ 6 Rule: "Three-way canals are not allowed."
    -- If a tile is adjacent to 3 or more water/city endpoints, it forms an illegal 3-way junction.
    -- A valid Canal must have EXACTLY 2 connectable endpoints!
    if #connectables ~= 2 then
        return false;
    end

    local a = connectables[1];
    local b = connectables[2];

    -- Must connect: Water + Water OR Water + City Center
    -- (Cannot connect City + City, and at least one side must be water)
    local hasWater = a.IsWater or b.IsWater;
    local isCityToCity = a.IsCity and b.IsCity;
    if not hasWater or isCityToCity then
        return false;
    end

    -- Rule: Endpoints cannot be adjacent to each other (dist >= 2).
    -- If they are adjacent (dist == 1), ships can already pass directly and Civ 6 forbids the hairpin turn.
    local distBetweenEndpoints = Map.GetPlotDistance(a.X, a.Y, b.X, b.Y);
    if distBetweenEndpoints < 2 then
        return false;
    end

    return true;
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
    DISTRICT_THANH = true, -- Vietnam unique Encampment: RequiresPopulation = false (free of Pop cap!)
    DISTRICT_SPACEPORT = true,
    DISTRICT_GOVERNMENT = true,
    DISTRICT_DIPLOMATIC_QUARTER = true,
    DISTRICT_HAG_MADAGASCAR_FOKO = true,
    DISTRICT_WONDER = true,
    DISTRICT_CITY_CENTER = true
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

-- Helper: Retrieve which city owns a given plot for a player
local function GetPlotOwningCity(plot, playerID)
    if plot == nil or not plot:IsOwned() then return nil; end
    if playerID ~= nil and plot:GetOwner() ~= playerID then return nil; end
    if Cities ~= nil and Cities.GetPlotPurchaseCity ~= nil then
        local pcallOk, c = pcall(function() return Cities.GetPlotPurchaseCity(plot); end);
        if pcallOk and c ~= nil then return c; end
    end
    if CityManager ~= nil and CityManager.GetPlotOwner ~= nil then
        local pcallOk, pPlayerID, pCityID = pcall(function() return CityManager.GetPlotOwner(plot); end);
        if pcallOk and pCityID ~= nil and pCityID ~= -1 then
            local pPlayer = Players[pPlayerID or playerID];
            if pPlayer and pPlayer:GetCities() then
                return pPlayer:GetCities():FindID(pCityID);
            end
        end
    end
    return nil;
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

-- Safe Aqueduct Position Checker (checks engine function if present, with bulletproof standalone fallback)
local function SafeIsValidAqueductPosition(playerID, px, py, cityX, cityY)
    if IsValidAqueductPosition ~= nil then
        local pcallOk, res = pcall(function() return IsValidAqueductPosition(playerID, px, py); end);
        if pcallOk and res ~= nil then return res; end
    end
    local plot = Map.GetPlot(px, py);
    if plot == nil or plot:IsWater() or plot:IsMountain() then return false; end
    if cityX ~= nil and cityY ~= nil then
        if Map.GetPlotDistance(cityX, cityY, px, py) ~= 1 then return false; end
    end
    for _, adj in pairs(Map.GetAdjacentPlots(px, py)) do
        if adj ~= nil then
            if not (cityX ~= nil and adj:GetX() == cityX and adj:GetY() == cityY) then
                if plot:IsRiver() and plot:IsRiverCrossingToPlot(adj) then
                    return true;
                elseif adj:IsLake() or adj:IsMountain() then
                    return true;
                elseif adj:GetFeatureType() ~= -1 and GameInfo.Features[adj:GetFeatureType()] and GameInfo.Features[adj:GetFeatureType()].FeatureType == "FEATURE_OASIS" then
                    return true;
                end
            end
        end
    end
    return false;
end

-- Safe Dam Position Checker
local function SafeIsValidDamPosition(playerID, px, py)
    if IsValidDamPosition ~= nil then
        local pcallOk, res = pcall(function() return IsValidDamPosition(playerID, px, py); end);
        if pcallOk and res ~= nil then return res; end
    end
    local plot = Map.GetPlot(px, py);
    if plot == nil then return false; end
    return IsValidRiverFloodplainForDam(plot) and not IsDamAlreadyOnRiver(playerID, px, py);
end

-- Rule 5: Priority score calculation for sorting build sequence
local function CalculateDistrictPriority(item, cityHasFreshWater)
    local baseType = item.BaseDistrictType;
    local distType = item.DistrictType;
    local num = item.NumericBonus or 0;
    local score = 50;

    if baseType == "DISTRICT_CAMPUS" then
        score = 92 + num * 4;
        if distType == "DISTRICT_SEOWON" then score = 96 + num * 2; end
    elseif baseType == "DISTRICT_COMMERCIAL_HUB" or baseType == "DISTRICT_HARBOR" then
        score = 88 + num * 3;
        if distType == "DISTRICT_SUGUBA" then score = 92 + num * 3; end
    elseif baseType == "DISTRICT_GOVERNMENT" then
        score = 87; -- High priority non-specialty hub boosting all surrounding districts
    elseif baseType == "DISTRICT_HOLY_SITE" then
        score = 86 + num * 3;
        if distType == "DISTRICT_LAVRA" then score = 90 + num * 3; end
    elseif baseType == "DISTRICT_AQUEDUCT" then
        score = not cityHasFreshWater and 87 or 74;
        if distType == "DISTRICT_BATH" then score = score + 5; end
    elseif baseType == "DISTRICT_INDUSTRIAL_ZONE" then
        score = 85 + num * 3;
        if distType == "DISTRICT_HANSA" or distType == "DISTRICT_OPPIDUM" then
            score = 91 + num * 3;
        end
    elseif baseType == "DISTRICT_DAM" then
        score = 78;
    elseif baseType == "DISTRICT_DIPLOMATIC_QUARTER" then
        score = 76; -- Non-specialty 1-per-empire envoy boost
    elseif baseType == "DISTRICT_ENCAMPMENT" then
        if distType == "DISTRICT_THANH" then
            score = 80 + num * 2; -- Vietnam Thành is Non-Specialty (free of Pop cap!)
        else
            score = 72;
        end
    elseif baseType == "DISTRICT_ENTERTAINMENT_COMPLEX" then
        score = 70;
    elseif baseType == "DISTRICT_THEATER" then
        score = 68 + num * 2;
        if distType == "DISTRICT_ACROPOLIS" then score = 75 + num * 2; end
    elseif baseType == "DISTRICT_PRESERVE" then
        score = 65 + num * 2;
    elseif baseType == "DISTRICT_CANAL" then
        score = 55;
    elseif baseType == "DISTRICT_NEIGHBORHOOD" then
        score = 45;
        if distType == "DISTRICT_MBANZA" then score = 56; end
    elseif baseType == "DISTRICT_AERODROME" then
        score = 35;
    elseif baseType == "DISTRICT_SPACEPORT" then
        score = 30 + num * 2;
        local hasRocketry = false;
        pcall(function()
            local pPlayer = Players[Game.GetLocalPlayer()];
            if pPlayer and pPlayer:GetTechs() and GameInfo.Technologies["TECH_ROCKETRY"] then
                hasRocketry = pPlayer:GetTechs():HasTech(GameInfo.Technologies["TECH_ROCKETRY"].Index);
            end
        end);
        if hasRocketry then
            score = score + 45; -- Prioritize rushing Spaceport for Science Victory once Rocketry is researched
        end
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
    local playerCfg = PlayerConfigurations[playerID];

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

    -- 3. Ring 1 & Ring 2 Yields with Existing City Protection
    -- For cities 2, 3, 4: Deduct cannibalization points and ignore phantom yields from tiles already claimed by existing cities!
    local pPlayer = Players[playerID];
    local pCities = pPlayer and pPlayer:GetCities();
    local cityCount = pCities and pCities:GetCount() or 0;
    local existingCitiesList = {};
    if cityCount >= 1 then
        for _, ec in pCities:Members() do
            if ec ~= nil then
                table.insert(existingCitiesList, {
                    City = ec,
                    X = ec:GetX(),
                    Y = ec:GetY(),
                    Name = Locale.Lookup(ec:GetName())
                });
            end
        end
    end

    local cannibalizedTilesCount = 0;
    local freshTilesCount = 0;

    -- Ring 1 Yields (6 hexes)
    local ring1Plots = Map.GetAdjacentPlots(px, py);
    for _, adjPlot in pairs(ring1Plots) do
        if adjPlot ~= nil and IsPlotVisibleOrRevealed(adjPlot, playerID) and not adjPlot:IsImpassable() then
            local f = adjPlot:GetYield(GameInfo.Yields["YIELD_FOOD"].Index);
            local p = adjPlot:GetYield(GameInfo.Yields["YIELD_PRODUCTION"].Index);
            local g = adjPlot:GetYield(GameInfo.Yields["YIELD_GOLD"].Index);
            local s = adjPlot:GetYield(GameInfo.Yields["YIELD_SCIENCE"].Index);
            local c = adjPlot:GetYield(GameInfo.Yields["YIELD_CULTURE"].Index);
            local faith = adjPlot:GetYield(GameInfo.Yields["YIELD_FAITH"].Index);

            local isRing1OfExisting = false;
            local isRing2OfExisting = false;
            local isOwnedByExisting = false;
            local hasExistingDistrict = false;

            if #existingCitiesList > 0 then
                for _, ec in ipairs(existingCitiesList) do
                    local d = Map.GetPlotDistance(adjPlot:GetX(), adjPlot:GetY(), ec.X, ec.Y);
                    if d <= 1 then
                        isRing1OfExisting = true;
                        break;
                    elseif d == 2 then
                        isRing2OfExisting = true;
                    end
                end
                if adjPlot:IsOwned() and adjPlot:GetOwner() == playerID then
                    isOwnedByExisting = true;
                end
                local dType = adjPlot:GetDistrictType();
                if (dType ~= nil and dType ~= -1) or adjPlot:IsCity() or m_AutoDistrictPins[adjPlot:GetX() .. "_" .. adjPlot:GetY()] ~= nil or (playerCfg ~= nil and HasManualPinAtPlot(playerCfg, adjPlot:GetX(), adjPlot:GetY())) then
                    hasExistingDistrict = true;
                end
            end

            if isRing1OfExisting then
                -- Tile belongs permanently to existing city (Engine Locked!). Cannot be worked or swapped!
                score = score - 8;
                cannibalizedTilesCount = cannibalizedTilesCount + 1;
            elseif isOwnedByExisting or hasExistingDistrict then
                -- Already claimed or constructed by an existing city!
                score = score - 4;
                cannibalizedTilesCount = cannibalizedTilesCount + 1;
            elseif isRing2OfExisting then
                -- In Ring 2 of existing city (contested border): heavily discounted yields
                score = score - 2;
                cannibalizedTilesCount = cannibalizedTilesCount + 1;
                score = score + (f * 0.7) + (p * 0.8);
            else
                -- Fresh new workable land for the empire!
                freshTilesCount = freshTilesCount + 1;
                score = score + 2; -- Expansion bonus per fresh tile
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
    end

    -- 4. Ring 2 Yields (12 hexes)
    local allWithin2 = GetPlotsWithinXTiles(px, py, 2);
    for _, plot2 in ipairs(allWithin2) do
        local dist = Map.GetPlotDistance(px, py, plot2:GetX(), plot2:GetY());
        if dist == 2 and IsPlotVisibleOrRevealed(plot2, playerID) and not plot2:IsImpassable() then
            local f = plot2:GetYield(GameInfo.Yields["YIELD_FOOD"].Index);
            local p = plot2:GetYield(GameInfo.Yields["YIELD_PRODUCTION"].Index);

            local isRing1OfExisting = false;
            local isRing2OfExisting = false;
            local isOwnedByExisting = false;
            local hasExistingDistrict = false;

            if #existingCitiesList > 0 then
                for _, ec in ipairs(existingCitiesList) do
                    local d = Map.GetPlotDistance(plot2:GetX(), plot2:GetY(), ec.X, ec.Y);
                    if d <= 1 then
                        isRing1OfExisting = true;
                        break;
                    elseif d == 2 then
                        isRing2OfExisting = true;
                    end
                end
                if plot2:IsOwned() and plot2:GetOwner() == playerID then
                    isOwnedByExisting = true;
                end
                local dType = plot2:GetDistrictType();
                if (dType ~= nil and dType ~= -1) or plot2:IsCity() or m_AutoDistrictPins[plot2:GetX() .. "_" .. plot2:GetY()] ~= nil or (playerCfg ~= nil and HasManualPinAtPlot(playerCfg, plot2:GetX(), plot2:GetY())) then
                    hasExistingDistrict = true;
                end
            end

            if isRing1OfExisting then
                score = score - 4;
                cannibalizedTilesCount = cannibalizedTilesCount + 1;
            elseif isOwnedByExisting or hasExistingDistrict then
                score = score - 2;
                cannibalizedTilesCount = cannibalizedTilesCount + 1;
            elseif isRing2OfExisting then
                score = score + (f * 0.4) + (p * 0.5);
            else
                freshTilesCount = freshTilesCount + 1;
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
    end

    if #existingCitiesList > 0 then
        if freshTilesCount >= 8 then
            score = score + 15;
            table.insert(reasons, string.format("พื้นที่ขยายอาณาจักรใหม่ %d ช่อง (+15)", freshTilesCount));
        end
        if cannibalizedTilesCount >= 5 then
            score = score - (cannibalizedTilesCount * 3);
            table.insert(reasons, string.format("ทับซ้อนพื้นที่เมืองเดิม %d ช่อง (-%d)", cannibalizedTilesCount, cannibalizedTilesCount * 3));
        end
    end

    -- 4.5 District Potential & Specialized Civilization Forensics
    -- A. Aqueduct + Dam + Industrial Zone Golden Combo Detection
    local candidateAQPlots = {};
    local candidateDamPlots = {};

    -- Scan Ring 1 for Aqueduct
    for _, p1 in pairs(ring1Plots) do
        if p1 ~= nil and not p1:IsWater() and not p1:IsMountain() and not p1:IsImpassable() then
            if not HasForbiddenResourceForDistrict(playerID, p1) then
                if SafeIsValidAqueductPosition(playerID, p1:GetX(), p1:GetY(), px, py) then
                    table.insert(candidateAQPlots, p1);
                end
            end
        end
    end

    -- Scan Rings 1 & 2 for Dam
    for _, pDam in ipairs(allWithin2) do
        local d = Map.GetPlotDistance(px, py, pDam:GetX(), pDam:GetY());
        if d >= 1 and d <= 2 and not pDam:IsWater() and not pDam:IsImpassable() then
            if not HasForbiddenResourceForDistrict(playerID, pDam) then
                if IsValidRiverFloodplainForDam(pDam) and not IsDamAlreadyOnRiver(playerID, pDam:GetX(), pDam:GetY()) then
                    table.insert(candidateDamPlots, pDam);
                end
            end
        end
    end

    local hasGoldenTripleCombo = false;
    local hasAqueductIZPair = false;

    if #candidateAQPlots > 0 and #candidateDamPlots > 0 then
        -- Check if any workable plot touches BOTH an Aqueduct candidate and a Dam candidate
        for _, pMid in ipairs(allWithin2) do
            local midX, midY = pMid:GetX(), pMid:GetY();
            local d = Map.GetPlotDistance(px, py, midX, midY);
            if d >= 1 and d <= 3 and not pMid:IsWater() and not pMid:IsMountain() and not pMid:IsImpassable() then
                if not HasForbiddenResourceForDistrict(playerID, pMid) then
                    local touchesAQ = false;
                    local touchesDam = false;
                    for _, aq in ipairs(candidateAQPlots) do
                        if Map.GetPlotDistance(midX, midY, aq:GetX(), aq:GetY()) == 1 and (midX ~= aq:GetX() or midY ~= aq:GetY()) then
                            touchesAQ = true;
                            break;
                        end
                    end
                    for _, dm in ipairs(candidateDamPlots) do
                        if Map.GetPlotDistance(midX, midY, dm:GetX(), dm:GetY()) == 1 and (midX ~= dm:GetX() or midY ~= dm:GetY()) then
                            touchesDam = true;
                            break;
                        end
                    end
                    if touchesAQ and touchesDam then
                        hasGoldenTripleCombo = true;
                        break;
                    end
                end
            end
        end
    end

    if not hasGoldenTripleCombo and #candidateAQPlots > 0 then
        -- Check if any workable plot can pair with Aqueduct for IZ (+2 Production)
        for _, aq in ipairs(candidateAQPlots) do
            for _, adj in pairs(Map.GetAdjacentPlots(aq:GetX(), aq:GetY())) do
                local ax, ay = adj:GetX(), adj:GetY();
                local d = Map.GetPlotDistance(px, py, ax, ay);
                if d >= 1 and d <= 3 and not (ax == px and ay == py) and not adj:IsWater() and not adj:IsMountain() and not adj:IsImpassable() then
                    if not HasForbiddenResourceForDistrict(playerID, adj) then
                        hasAqueductIZPair = true;
                        break;
                    end
                end
            end
            if hasAqueductIZPair then break; end
        end
    end

    if hasGoldenTripleCombo then
        score = score + 26;
        table.insert(reasons, "สุดยอดคอมโบทองคำ เขื่อน + ส่งน้ำ + โรงงาน (+26)");
    elseif hasAqueductIZPair then
        score = score + 12;
        table.insert(reasons, "มีคอมโบ ส่งน้ำ + โรงงาน (+12)");
    end

    -- B. Science District Potential (Campus / Seowon / Observatory)
    local playerCivType = playerCfg and playerCfg:GetCivilizationTypeName() or "";
    local isKoreaCiv = (playerCivType == "CIVILIZATION_KOREA");
    local isMayaCiv = (playerCivType == "CIVILIZATION_MAYA");
    local isVietnamCiv = (playerCivType == "CIVILIZATION_VIETNAM");

    if isKoreaCiv then
        -- Korea: Seowon must be on Hills and should be in Ring 2 isolated from City Center
        local bestSeowonPlot = nil;
        local hasWorkableHills = false;
        for _, p2 in ipairs(allWithin2) do
            local d = Map.GetPlotDistance(px, py, p2:GetX(), p2:GetY());
            if d >= 1 and d <= 2 and p2:IsHills() and not p2:IsWater() and not p2:IsMountain() and not p2:IsImpassable() then
                hasWorkableHills = true;
                if not HasForbiddenResourceForDistrict(playerID, p2) then
                    if d == 2 then
                        bestSeowonPlot = p2;
                        break;
                    end
                end
            end
        end
        if bestSeowonPlot ~= nil then
            score = score + 14;
            table.insert(reasons, "มีเนินเขาวง 2 ชั้นยอดสำหรับ Seowon (+14)");
        elseif hasWorkableHills then
            score = score + 6;
            table.insert(reasons, "มีเนินเขาสำหรับ Seowon (+6)");
        else
            score = score - 20;
            table.insert(reasons, "เกาหลีแต่ไร้เนินเขาสำหรับสร้าง Seowon (-20)");
        end

    elseif isMayaCiv then
        -- Maya: Observatory gets +2 from Plantations, +0.5 from Farms
        local plantationCount = 0;
        local flatFarmableCount = 0;
        for _, p2 in ipairs(allWithin2) do
            local d = Map.GetPlotDistance(px, py, p2:GetX(), p2:GetY());
            if d >= 1 and d <= 2 and not p2:IsWater() and not p2:IsMountain() and not p2:IsImpassable() then
                local rIdx = p2:GetResourceType();
                if rIdx ~= -1 then
                    local rInfo = GameInfo.Resources[rIdx];
                    if rInfo ~= nil then
                        local rType = rInfo.ResourceType;
                        if rType == "RESOURCE_BANANAS" or rType == "RESOURCE_CITRUS" or rType == "RESOURCE_COCOA" or
                           rType == "RESOURCE_COFFEE" or rType == "RESOURCE_COTTON" or rType == "RESOURCE_DYES" or
                           rType == "RESOURCE_SILK" or rType == "RESOURCE_SPICES" or rType == "RESOURCE_SUGAR" or
                           rType == "RESOURCE_TEA" or rType == "RESOURCE_TOBACCO" then
                            plantationCount = plantationCount + 1;
                        end
                    end
                elseif not p2:IsHills() and not HasForbiddenResourceForDistrict(playerID, p2) then
                    flatFarmableCount = flatFarmableCount + 1;
                end
            end
        end
        if plantationCount >= 2 then
            score = score + 16;
            table.insert(reasons, string.format("แปลงเพาะปลูก %d จุดสำหรับ Observatory (+16)", plantationCount));
        elseif plantationCount == 1 then
            score = score + 10;
            table.insert(reasons, "มีแปลงเพาะปลูกสำหรับ Observatory (+10)");
        elseif flatFarmableCount >= 4 then
            score = score + 6;
            table.insert(reasons, "พื้นที่เกษตรกรรมกลุ่มสำหรับ Observatory (+6)");
        end

    else
        -- Standard Campus: Mountains, Reefs, Geothermal Fissures
        local bestCampusAdjacency = 0;
        for _, pCamp in ipairs(allWithin2) do
            local d = Map.GetPlotDistance(px, py, pCamp:GetX(), pCamp:GetY());
            if d >= 1 and d <= 2 and not pCamp:IsWater() and not pCamp:IsMountain() and not pCamp:IsImpassable() then
                if not HasForbiddenResourceForDistrict(playerID, pCamp) then
                    local adjSci = 0;
                    for _, adj in pairs(Map.GetAdjacentPlots(pCamp:GetX(), pCamp:GetY())) do
                        if adj:IsMountain() then adjSci = adjSci + 1; end
                        local fIdx = adj:GetFeatureType();
                        if fIdx ~= -1 and GameInfo.Features[fIdx] ~= nil then
                            local fType = GameInfo.Features[fIdx].FeatureType;
                            if fType == "FEATURE_GEOTHERMAL_FISSURE" or fType == "FEATURE_REEF" then
                                adjSci = adjSci + 2;
                            elseif fType == "FEATURE_JUNGLE" then
                                adjSci = adjSci + 0.5;
                            end
                        end
                    end
                    if adjSci > bestCampusAdjacency then
                        bestCampusAdjacency = adjSci;
                    end
                end
            end
        end
        if bestCampusAdjacency >= 4 then
            score = score + 16;
            table.insert(reasons, string.format("จุดสร้าง Campus ระดับเทพ (+%d Sci) (+16)", math.floor(bestCampusAdjacency)));
        elseif bestCampusAdjacency >= 3 then
            score = score + 10;
            table.insert(reasons, string.format("จุดสร้าง Campus ชั้นยอด (+%d Sci) (+10)", math.floor(bestCampusAdjacency)));
        elseif bestCampusAdjacency >= 2 then
            score = score + 5;
            table.insert(reasons, string.format("จุดสร้าง Campus มาตรฐาน (+%d Sci) (+5)", math.floor(bestCampusAdjacency)));
        end
    end

    -- C. Vietnam Feature Forensics
    if isVietnamCiv then
        local vietnamFeatureCount = 0;
        for _, p2 in ipairs(allWithin2) do
            local d = Map.GetPlotDistance(px, py, p2:GetX(), p2:GetY());
            if d >= 1 and d <= 2 and not p2:IsWater() and not p2:IsMountain() and not p2:IsImpassable() then
                if not HasForbiddenResourceForDistrict(playerID, p2) then
                    if IsValidVietnamFeature(p2) then
                        vietnamFeatureCount = vietnamFeatureCount + 1;
                    end
                end
            end
        end
        if vietnamFeatureCount == 0 then
            score = score - 70;
            table.insert(reasons, "วิกฤตเวียดนาม: ไร้ป่า/หนองน้ำสำหรับสร้างเขตพิเศษ (-70)");
        elseif vietnamFeatureCount == 1 then
            score = score - 35;
            table.insert(reasons, "เวียดนาม: มีป่า/หนองน้ำเพียง 1 ช่อง ไม่พอผังเขต (-35)");
        elseif vietnamFeatureCount >= 4 then
            score = score + 15;
            table.insert(reasons, string.format("เวียดนาม: ป่าและหนองน้ำ %d ช่อง อุดมสมบูรณ์สำหรับผังเขต (+15)", vietnamFeatureCount));
        end
    end

    -- D. Late-Game High-Tech Flat Land Potential (Spaceport & Aerodrome)
    local flatLandCount = 0;
    for _, p2 in ipairs(allWithin2) do
        local d = Map.GetPlotDistance(px, py, p2:GetX(), p2:GetY());
        if d >= 1 and d <= 2 and not p2:IsWater() and not p2:IsMountain() and not p2:IsHills() and not p2:IsImpassable() then
            if not HasForbiddenResourceForDistrict(playerID, p2) then
                flatLandCount = flatLandCount + 1;
            end
        end
    end
    if flatLandCount >= 4 and #candidateAQPlots > 0 then
        score = score + 4;
        table.insert(reasons, "มีที่ราบเปิดกว้างสำหรับเขตเทคโนโลยี/อวกาศ (+4)");
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
    if cityCount >= 1 then
        local minCityDist = 999;
        local nearestCity = nil;
        for _, city in ipairs(existingCitiesList) do
            local d = Map.GetPlotDistance(px, py, city.X, city.Y);
            if d < minCityDist then
                minCityDist = d;
                nearestCity = city;
            end
        end

        local nearestCityName = nearestCity and nearestCity.Name or "เมืองเดิม";

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
        -- dist == 4: +10 pts (Compact empire)
        -- dist == 5: +18 pts (Golden distance: zero inner ring overlap, district synergy, AoE buff)
        -- dist == 6: +10 pts (Standard workable distance)
        -- dist >= 7: -10 pts (Too far from empire)
        if minCityDist < 4 then
            return -9999, waterTag, {"ระยะใกล้เมืองเกินไป (< 4 ช่อง)"};
        elseif minCityDist == 4 then
            score = score + 10;
            table.insert(reasons, string.format("ระยะติดเมืองเดิม 4 ช่องจาก %s (+10)", nearestCityName));
            if hasNewResource then
                score = score + 10;
                table.insert(reasons, "เคลมแร่ใหม่ของอาณาจักร: " .. table.concat(newResNames, ", "));
            end
        elseif minCityDist == 5 then
            score = score + 18;
            table.insert(reasons, string.format("ระยะทองคำ 5 ช่องจาก %s (+18 ขยายอิสระไร้การทับซ้อน)", nearestCityName));
            if hasNewResource then
                score = score + 12;
                table.insert(reasons, "เคลมแร่ใหม่ของอาณาจักร: " .. table.concat(newResNames, ", "));
            end
        elseif minCityDist == 6 then
            score = score + 10;
            table.insert(reasons, string.format("ระยะมาตรฐาน 6 ช่องจาก %s (+10)", nearestCityName));
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
            UpdateSmartPlannerContextVisibility();
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
        UpdateSmartPlannerContextVisibility();
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

    local allCityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local cityPlotSet = {};
    for _, plot in ipairs(allCityPlots) do
        cityPlotSet[plot:GetX() .. "_" .. plot:GetY()] = true;
    end

    local pCity = CityManager and CityManager.GetCityAt and CityManager.GetCityAt(cityX, cityY);
    local isCapital = pCity and pCity.IsCapital and pCity:IsCapital() or false;
    local thisCityName = (pCity and pCity.GetName and pCity:GetName() ~= "") and Locale.Lookup(pCity:GetName()) or nil;

    local hasChanges = false;
    local allPins = playerCfg:GetMapPins();
    local pinsToDelete = {};
    if allPins ~= nil then
        for _, pin in pairs(allPins) do
            if pin ~= nil then
                local px, py = pin:GetHexX(), pin:GetHexY();
                local key = px .. "_" .. py;
                if cityPlotSet[key] then
                    local pinName = pin:GetName() or "";
                    local autoInfo = m_AutoDistrictPins[key];
                    local isAutoPin = (autoInfo ~= nil) or pinName:match("^%[.-%]%s*#%d") or pinName:match("^%[เมือง");

                    if isAutoPin then
                        local shouldDelete = false;

                        if autoInfo ~= nil then
                            if autoInfo.CityX == cityX and autoInfo.CityY == cityY then
                                shouldDelete = true;
                            elseif isCapital then
                                -- Capital priority: if secondary city placed a pin in Capital's Ring 1 or 2 (dist <= 2), Capital reclaims it!
                                local distToCap = Map.GetPlotDistance(px, py, cityX, cityY);
                                if distToCap <= 2 then
                                    print(string.format("DMT: Capital reclaiming inner ring tile at (%d, %d) from secondary city!", px, py));
                                    shouldDelete = true;
                                end
                            end
                        else
                            -- Fallback name check if autoInfo table not in memory
                            if thisCityName ~= nil and thisCityName ~= "" then
                                local escaped = thisCityName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1");
                                if pinName:match("^%[" .. escaped .. "%]") then
                                    shouldDelete = true;
                                end
                            end
                            if not shouldDelete and isCapital then
                                local distToCap = Map.GetPlotDistance(px, py, cityX, cityY);
                                if distToCap <= 2 then
                                    shouldDelete = true;
                                end
                            end
                        end

                        if shouldDelete then
                            table.insert(pinsToDelete, { ID = pin:GetID(), Pin = pin, Key = key });
                        end
                    end
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
        UpdateSmartPlannerContextVisibility();
    end

    ClearAutoDistrictsForCity(playerID, cityX, cityY);

    -- Requirement 2: Ensure Capital districts are calculated first before secondary city planning
    if not isCapital and pPlayer:GetCities() ~= nil then
        local capitalCity = pPlayer:GetCities():GetCapitalCity();
        if capitalCity ~= nil and (capitalCity:GetX() ~= cityX or capitalCity:GetY() ~= cityY) then
            -- Check if Capital already has any auto pins in memory or on map
            local capitalHasPins = false;
            for _, info in pairs(m_AutoDistrictPins) do
                if type(info) == "table" and (info.IsCapital or (info.CityX == capitalCity:GetX() and info.CityY == capitalCity:GetY())) then
                    capitalHasPins = true;
                    break;
                end
            end
            if not capitalHasPins then
                print(string.format("DMT: Secondary city [%s] planning, but Capital [%s] has no planned districts yet. Prioritizing Capital first!",
                    cityName, Locale.Lookup(capitalCity:GetName())));
                OptimizeCityDistricts(playerID, capitalCity:GetX(), capitalCity:GetY(), capitalCity:GetID(), false);
            end
        end
    end

    -- Rule 3: Enforce Workable Range (1 - 3 tiles strictly)
    local allCityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local candidatePlots = {};
    local occupiedPlots = {};

    occupiedPlots[Map.GetPlot(cityX, cityY):GetIndex()] = true;

    -- Cache all cities on the map (both player's and other civs/city-states) for Engine-Lock, Anti-Encroachment & Capital Protection
    local allCitiesOnMap = {};
    local otherFriendlyCities = {};
    local capitalX, capitalY = nil, nil;
    if pPlayer and pPlayer:GetCities() ~= nil then
        local cap = pPlayer:GetCities():GetCapitalCity();
        if cap ~= nil then
            capitalX = cap:GetX();
            capitalY = cap:GetY();
        end
    end

    local thisCityID = (pCity and pCity:GetID()) or cityID;
    local alivePlayers = Game.GetPlayers{Alive = true};
    for _, aPlayer in ipairs(alivePlayers) do
        local aPlayerID = aPlayer:GetID();
        local aCities = aPlayer:GetCities();
        if aCities ~= nil then
            for _, c in aCities:Members() do
                if c ~= nil then
                    local cx, cy = c:GetX(), c:GetY();
                    local cID = c:GetID();
                    -- STRICT RULE: Must NEVER include THIS city (the city currently being planned) in allCitiesOnMap!
                    local isThisCity = (aPlayerID == playerID) and ((cx == cityX and cy == cityY) or (thisCityID ~= nil and thisCityID ~= -1 and cID == thisCityID));
                    if not isThisCity then
                        local isSame = (aPlayerID == playerID);
                        local isCap = false;
                        pcall(function() if c.IsCapital then isCap = c:IsCapital(); end end);
                        local cName = "City";
                        pcall(function() if c.GetName then cName = Locale.Lookup(c:GetName()); end end);
                        local cityEntry = {
                            City = c,
                            CityID = cID,
                            X = cx,
                            Y = cy,
                            Owner = aPlayerID,
                            IsSamePlayer = isSame,
                            IsCapital = isCap,
                            Name = cName
                        };
                        table.insert(allCitiesOnMap, cityEntry);
                        if isSame then
                            table.insert(otherFriendlyCities, cityEntry);
                        end
                    end
                end
            end
        end
    end

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

        -- Check tile ownership: plot owned by another friendly city!
        local owningCity = GetPlotOwningCity(plot, playerID);
        local isOwnedByAnotherCity = false;
        if owningCity ~= nil then
            local ocX, ocY = owningCity:GetX(), owningCity:GetY();
            local ocID = owningCity:GetID();
            if (thisCityID ~= nil and ocID ~= thisCityID) or (ocX ~= cityX or ocY ~= cityY) then
                isOwnedByAnotherCity = true;
            end
        end

        -- Proximity to nearest OTHER city across the entire map (strictly excluding this city!)
        local minDistToAnyCity = 999;
        local nearestCity = nil;
        for _, oc in ipairs(allCitiesOnMap) do
            if not (oc.X == cityX and oc.Y == cityY) and (thisCityID == nil or oc.CityID ~= thisCityID or not oc.IsSamePlayer) then
                local d = Map.GetPlotDistance(px, py, oc.X, oc.Y);
                if d < minDistToAnyCity then
                    minDistToAnyCity = d;
                    nearestCity = oc;
                end
            end
        end

        -- REQUIREMENT 1 & 2: Engine Lock & Zero-Tolerance Core Encroachment
        -- Civ 6 rule: Ring 1 of ANY city is Engine Locked (cannot swap). Ring 2 is core workable territory.
        -- Strictly forbid ANY specialty/infrastructure district if plot is within 2 tiles of ANY other city (minDistToAnyCity <= 2)!
        local isInvadingOtherCityCore = (minDistToAnyCity <= 2);

        -- Capital Starvation Prevention (Rings 1 & 2 of Capital are locked to Capital!)
        local isCapitalProtected = false;
        if not isCapital and capitalX ~= nil and capitalY ~= nil then
            local distToCap = Map.GetPlotDistance(px, py, capitalX, capitalY);
            if distToCap <= 2 then -- Rings 1 & 2 of Capital strictly reserved for Capital
                isCapitalProtected = true;
            end
        end

        -- REQUIREMENT 3: Natural Sphere of Influence / Anti-Encroachment
        -- Never plan a district on a tile that is CLOSER to another city than to THIS city!
        local isCloserToOtherCity = (minDistToAnyCity < distFromCity);

        -- Never plan a district on outer border (Ring 3) if within 3 tiles of another city
        local isContestedBorder = (distFromCity == 3 and minDistToAnyCity <= 3);

        -- REQUIREMENT 4: Do not steal pins already planned for another city (especially Capital)
        local isClaimedByOtherCity = false;
        local autoInfo = m_AutoDistrictPins[px .. "_" .. py];
        if autoInfo ~= nil then
            if autoInfo.CityX ~= cityX or autoInfo.CityY ~= cityY then
                isClaimedByOtherCity = true;
            end
        else
            local pinOnMap = GetPinAtPlot(playerCfg, px, py);
            if pinOnMap ~= nil then
                local pName = pinOnMap:GetName() or "";
                local pinCity = pName:match("^%[(.-)%]%s*#%d");
                if pinCity ~= nil and cityName ~= nil and pinCity ~= cityName then
                    isClaimedByOtherCity = true;
                end
            end
        end

        if isOutOfRange or hasExistingDistrict or isForeignOwned or isOwnedByAnotherCity or isImpassable or hasManualPin or hasForbiddenRes or isInvadingOtherCityCore or isCapitalProtected or isCloserToOtherCity or isContestedBorder or isClaimedByOtherCity then
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
    local distPreserve      = GetPlayerUniqueDistrict(playerID, "DISTRICT_PRESERVE");

    -- Rule 4: Civilization and Unique District Detection
    local playerConfig = PlayerConfigurations[playerID];
    local civType = playerConfig and playerConfig:GetCivilizationTypeName() or "";
    local isVietnam = (civType == "CIVILIZATION_VIETNAM" or distEncampment == "DISTRICT_THANH");
    local isKorea = (civType == "CIVILIZATION_KOREA" or distCampus == "DISTRICT_SEOWON");
    local isGaul = (civType == "CIVILIZATION_GAUL" or distIZ == "DISTRICT_OPPIDUM");
    local isKongo = (civType == "CIVILIZATION_KONGO" or distNeighborhood == "DISTRICT_MBANZA");
    local isGermany = (civType == "CIVILIZATION_GERMANY" or distIZ == "DISTRICT_HANSA");
    local isRome = (civType == "CIVILIZATION_ROME" or distAqueduct == "DISTRICT_BATH");
    local isMaya = (civType == "CIVILIZATION_MAYA" or distCampus == "DISTRICT_OBSERVATORY");
    local isGreece = (civType == "CIVILIZATION_GREECE" or distTheater == "DISTRICT_ACROPOLIS");
    local isMali = (civType == "CIVILIZATION_MALI" or distCommHub == "DISTRICT_SUGUBA");
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
                if dTypeName == "DISTRICT_THANH" then
                    bIsSpec = false; -- Vietnam Thành is Non-Specialty (free of Pop cap!)
                elseif dInfo.RequiresPopulation == true or dInfo.RequiresPopulation == 1 or specialtyBaseTypes[baseType] then
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
    -- Scored optimization: Prioritize Ring 1/2 of THIS city, Aqueduct & Industrial Zone synergy, STRICTLY forbid sticking to another city!
    local bestDam = nil;
    local bestDamScore = -9999;
    if not CityHasDistrict("DISTRICT_DAM") and GameInfo.Districts[distDam] ~= nil then
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidRiverFloodplainForDam(plot) and not IsDamAlreadyOnRiver(playerID, px, py) and SafeIsValidDamPosition(playerID, px, py) then
                    local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);

                    -- Check distance to all OTHER cities on map (strictly excluding this city!)
                    local minOtherDist = 999;
                    for _, oc in ipairs(allCitiesOnMap) do
                        if not (oc.X == cityX and oc.Y == cityY) and (thisCityID == nil or oc.CityID ~= thisCityID or not oc.IsSamePlayer) then
                            local d = Map.GetPlotDistance(px, py, oc.X, oc.Y);
                            if d < minOtherDist then
                                minOtherDist = d;
                            end
                        end
                    end

                    -- Strict Dam Rejections:
                    -- 1. Never in Ring 1 of ANY other city (Engine Lock)
                    -- 2. Never in Ring 2 of another city if distFromCity >= 2 (Never stick to another city!)
                    -- 3. Never closer to another city than to THIS city
                    -- 4. Never Ring 3 Dam if it's within 3 tiles of another city
                    local bDamValid = true;
                    if minOtherDist < 2 then
                        bDamValid = false;
                    elseif minOtherDist <= 2 and distFromCity >= 2 then
                        bDamValid = false;
                    elseif minOtherDist < distFromCity then
                        bDamValid = false;
                    elseif distFromCity == 3 and minOtherDist <= 3 then
                        bDamValid = false;
                    end

                    if bDamValid then
                        local score = 0;

                        -- Distance preference (Ring 1 > Ring 2 >> Ring 3)
                        if distFromCity == 1 then
                            score = score + 50; -- Ring 1: adjacent to city center, best!
                        elseif distFromCity == 2 then
                            score = score + 25; -- Ring 2: close workable tile
                        elseif distFromCity == 3 then
                            score = score - 20; -- Ring 3: outer edge, heavily penalized
                        end

                        -- Safety distance from other cities
                        if minOtherDist >= 4 then
                            score = score + 15;
                        elseif minOtherDist == 3 then
                            score = score + 5;
                        end

                        -- Aqueduct synergy: can this Dam be adjacent to a candidate Ring 1 Aqueduct?
                        local canTouchAqueduct = false;
                        local openAdjacentCount = 0;
                        for _, adj in pairs(Map.GetAdjacentPlots(px, py)) do
                            local ax, ay = adj:GetX(), adj:GetY();
                            if Map.GetPlotDistance(cityX, cityY, ax, ay) == 1 then
                                if IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                                    if SafeIsValidAqueductPosition(playerID, ax, ay, cityX, cityY) then
                                        canTouchAqueduct = true;
                                    end
                                end
                            end
                            if IsPlotAvailable(adj, false) and not adj:IsWater() and not adj:IsMountain() then
                                openAdjacentCount = openAdjacentCount + 1;
                            end
                        end

                        if canTouchAqueduct then
                            score = score + 35; -- Critical: empowers Aqueduct + Dam + Industrial Zone synergy!
                        end
                        score = score + (openAdjacentCount * 4);

                        if plot:IsOwned() and plot:GetOwner() == playerID then
                            score = score + 10;
                        end

                        if score > bestDamScore then
                            bestDamScore = score;
                            bestDam = plot;
                        end
                    end
                end
            end
        end
    end
    if bestDamScore <= 0 then
        bestDam = nil;
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
                if Map.GetPlotDistance(cityX, cityY, px, py) == 1 and SafeIsValidAqueductPosition(playerID, px, py, cityX, cityY) then
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
                aqueductYieldBonus = "+2 Housing, +1 Amenity (อ่างอาบน้ำโรมัน)";

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

    -- Step D: Industrial Zone (Specialty) - Unique Districts: Hansa (Germany), Oppidum (Gaul)
    local bestIZ = nil;
    if not CityHasDistrict("DISTRICT_INDUSTRIAL_ZONE") and GameInfo.Districts[distIZ] ~= nil then
        local bestIZScore = -1;
        local isHansa = (isGermany or distIZ == "DISTRICT_HANSA");
        local isOppidum = (isGaul or distIZ == "DISTRICT_OPPIDUM");

        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            -- Gaul Oppidum rule: Strictly forbidden adjacent to City Center (dist >= 2)!
            local bGaulValid = (not isOppidum) or (distFromCity >= 2);

            if bGaulValid and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distIZ, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local izScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);

                    if isHansa then
                        -- Hansa (Germany): +2 Aqueduct, Dam, Canal, Commercial Hub; +1 per adjacent Resource!
                        for _, adj in pairs(adjPlots) do
                            local adjIdx = adj:GetIndex();
                            if effectiveAqueductPlot and adjIdx == effectiveAqueductPlot:GetIndex() then izScore = izScore + 2; end
                            if effectiveDamPlot and adjIdx == effectiveDamPlot:GetIndex() then izScore = izScore + 2; end
                            if effectiveCanalPlot and adjIdx == effectiveCanalPlot:GetIndex() then izScore = izScore + 2; end
                            if (effectiveCommHubPlot and adjIdx == effectiveCommHubPlot:GetIndex()) or (adj:GetDistrictType() ~= -1 and (GameInfo.Districts[adj:GetDistrictType()].DistrictType == "DISTRICT_COMMERCIAL_HUB" or GameInfo.Districts[adj:GetDistrictType()].DistrictType == "DISTRICT_SUGUBA")) then
                                izScore = izScore + 2;
                            end
                            local rIdx = adj:GetResourceType();
                            if rIdx ~= -1 then
                                izScore = izScore + 1; -- +1 per adjacent Resource of ANY kind!
                            end
                            if assignedPlots[adjIdx] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                izScore = izScore + 0.5;
                            end
                        end
                    elseif isOppidum then
                        -- Oppidum (Gaul): +2 per Strategic Resource, +2 per Quarry, +0.5 per District
                        for _, adj in pairs(adjPlots) do
                            local rIdx = adj:GetResourceType();
                            if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                                izScore = izScore + 2;
                            end
                            local impIdx = adj:GetImprovementType();
                            if impIdx ~= -1 and GameInfo.Improvements[impIdx] and GameInfo.Improvements[impIdx].ImprovementType == "IMPROVEMENT_QUARRY" then
                                izScore = izScore + 2;
                            elseif rIdx ~= -1 and GameInfo.Resources[rIdx] and (GameInfo.Resources[rIdx].ResourceType == "RESOURCE_STONE" or GameInfo.Resources[rIdx].ResourceType == "RESOURCE_GYPSUM" or GameInfo.Resources[rIdx].ResourceType == "RESOURCE_MARBLE") then
                                izScore = izScore + 2;
                            end
                            if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                izScore = izScore + 0.5;
                            end
                        end
                    else
                        -- Standard Industrial Zone: +2 Aqueduct/Dam/Canal, +1 Strategic, +0.5 Mine/Quarry, +0.5 District
                        for _, adj in pairs(adjPlots) do
                            local adjIdx = adj:GetIndex();
                            if effectiveAqueductPlot and adjIdx == effectiveAqueductPlot:GetIndex() then izScore = izScore + 2; end
                            if effectiveDamPlot and adjIdx == effectiveDamPlot:GetIndex() then izScore = izScore + 2; end
                            if effectiveCanalPlot and adjIdx == effectiveCanalPlot:GetIndex() then izScore = izScore + 2; end
                            local rIdx = adj:GetResourceType();
                            if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                                izScore = izScore + 1;
                            end
                            local tIdx = adj:GetTerrainType();
                            if tIdx ~= -1 and GameInfo.Terrains[tIdx] and GameInfo.Terrains[tIdx].Hills then
                                izScore = izScore + 0.5;
                            end
                            if assignedPlots[adjIdx] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                izScore = izScore + 0.5;
                            end
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
            local yieldText = "+" .. izBonus .. " [ICON_Production] Prod";
            if isHansa then
                yieldText = "+" .. izBonus .. " [ICON_Production] Prod (Hansa โบนัสแร่+เขต)";
            elseif isOppidum then
                yieldText = "+" .. izBonus .. " [ICON_Production] Prod (Oppidum แร่ยุทธศาสตร์)";
            end
            table.insert(plannedDistricts, {
                Plot = bestIZ,
                DistrictType = distIZ,
                BaseDistrictType = "DISTRICT_INDUSTRIAL_ZONE",
                BaseName = Locale.Lookup(GameInfo.Districts[distIZ].Name),
                YieldBonus = yieldText,
                NumericBonus = izBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveIZPlot = bestIZ or GetExistingDistrictPlot("DISTRICT_INDUSTRIAL_ZONE");

    -- Step E: Harbor (Specialty) - Unique Districts: Cothon (Phoenicia), Royal Navy Dockyard (England)
    local bestHarbor = nil;
    if not CityHasDistrict("DISTRICT_HARBOR") and GameInfo.Districts[distHarbor] ~= nil then
        local bestHarborScore = -1;
        local isCothon = (distHarbor == "DISTRICT_COTHON");
        local isRND = (distHarbor == "DISTRICT_ROYAL_NAVY_DOCKYARD");

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
            local yieldText = "+" .. hBonus .. " [ICON_Gold] Gold";
            if isCothon then
                yieldText = "+" .. hBonus .. " [ICON_Gold] Gold & +50% Naval/Settler";
            elseif isRND then
                yieldText = "+" .. hBonus .. " [ICON_Gold] Gold & +4 Ship Move";
            end
            table.insert(plannedDistricts, {
                Plot = bestHarbor,
                DistrictType = distHarbor,
                BaseDistrictType = "DISTRICT_HARBOR",
                BaseName = Locale.Lookup(GameInfo.Districts[distHarbor].Name),
                YieldBonus = yieldText,
                NumericBonus = hBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveHarborPlot = bestHarbor or GetExistingDistrictPlot("DISTRICT_HARBOR");

    -- Step F: Commercial Hub (Specialty) - Unique District: Suguba (Mali)
    local bestCommHub = nil;
    if not CityHasDistrict("DISTRICT_COMMERCIAL_HUB") and GameInfo.Districts[distCommHub] ~= nil then
        local bestCHScore = -1;
        local isSuguba = (isMali or distCommHub == "DISTRICT_SUGUBA");

        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCommHub, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local chScore = 0;
                    if plot:IsRiver() then chScore = chScore + 2; end
                    local adjPlots = Map.GetAdjacentPlots(px, py);

                    if isSuguba then
                        -- Suguba (Mali): +2 River, +2 Holy Site/Lavra, +1 per adjacent District!
                        for _, adj in pairs(adjPlots) do
                            local adjIdx = adj:GetIndex();
                            if (effectiveHolySitePlot and adjIdx == effectiveHolySitePlot:GetIndex()) or (adj:GetDistrictType() ~= -1 and (GameInfo.Districts[adj:GetDistrictType()].DistrictType == "DISTRICT_HOLY_SITE" or GameInfo.Districts[adj:GetDistrictType()].DistrictType == "DISTRICT_LAVRA")) then
                                chScore = chScore + 2;
                            end
                            if assignedPlots[adjIdx] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                chScore = chScore + 1; -- Major +1 per adjacent district!
                            end
                        end
                    else
                        -- Standard Commercial Hub: +2 River, +2 Harbor, +0.5 District
                        for _, adj in pairs(adjPlots) do
                            if effectiveHarborPlot and adj:GetIndex() == effectiveHarborPlot:GetIndex() then
                                chScore = chScore + 2;
                            end
                            if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                chScore = chScore + 0.5;
                            end
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
            local yieldText = "+" .. chBonus .. " [ICON_Gold] Gold";
            if isSuguba then
                yieldText = "+" .. chBonus .. " [ICON_Gold] Gold (Suguba ริมแม่น้ำ+ศาสนา)";
            end
            table.insert(plannedDistricts, {
                Plot = bestCommHub,
                DistrictType = distCommHub,
                BaseDistrictType = "DISTRICT_COMMERCIAL_HUB",
                BaseName = Locale.Lookup(GameInfo.Districts[distCommHub].Name),
                YieldBonus = yieldText,
                NumericBonus = chBonus,
                IsSpecialty = true
            });
        end
    end
    local effectiveCommHubPlot = bestCommHub or GetExistingDistrictPlot("DISTRICT_COMMERCIAL_HUB");

    -- Step G: Campus (Specialty) - Unique Districts: Seowon (Korea), Observatory (Maya)
    local bestCampus = nil;
    if not CityHasDistrict("DISTRICT_CAMPUS") and GameInfo.Districts[distCampus] ~= nil then
        local bestCampusScore = -1;
        local isSeowon = (isKorea or distCampus == "DISTRICT_SEOWON");
        local isObs = (isMaya or distCampus == "DISTRICT_OBSERVATORY");

        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            if IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distCampus, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    if isSeowon then
                        -- Seowon: MUST be on Hills! Base +4 Science, -1 per adjacent district. Must be isolated!
                        if plot:IsHills() then
                            local numAdjDistricts = 0;
                            local adjPlots = Map.GetAdjacentPlots(px, py);
                            for _, adj in pairs(adjPlots) do
                                if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                    numAdjDistricts = numAdjDistricts + 1;
                                end
                            end
                            local seowonScore = 4 - numAdjDistricts;
                            -- Prefer 0 adjacent districts and distance >= 2 from city center
                            if Map.GetPlotDistance(cityX, cityY, px, py) >= 2 and numAdjDistricts == 0 then
                                seowonScore = seowonScore + 2;
                            end
                            if seowonScore > bestCampusScore then
                                bestCampusScore = seowonScore;
                                bestCampus = plot;
                            end
                        end
                    elseif isObs then
                        -- Observatory: +2 per adjacent Plantation, +0.5 per adjacent Farm, +0.5 per District
                        local obsScore = 0;
                        local adjPlots = Map.GetAdjacentPlots(px, py);
                        for _, adj in pairs(adjPlots) do
                            local rIdx = adj:GetResourceType();
                            if rIdx ~= -1 then
                                local rInfo = GameInfo.Resources[rIdx];
                                if rInfo ~= nil then
                                    local rType = rInfo.ResourceType;
                                    if rType == "RESOURCE_BANANAS" or rType == "RESOURCE_CITRUS" or rType == "RESOURCE_COCOA" or
                                       rType == "RESOURCE_COFFEE" or rType == "RESOURCE_COTTON" or rType == "RESOURCE_DYES" or
                                       rType == "RESOURCE_SILK" or rType == "RESOURCE_SPICES" or rType == "RESOURCE_SUGAR" or
                                       rType == "RESOURCE_TEA" or rType == "RESOURCE_TOBACCO" then
                                        obsScore = obsScore + 2;
                                    end
                                end
                            elseif not adj:IsHills() and not adj:IsMountain() and not adj:IsWater() then
                                obsScore = obsScore + 0.5;
                            end
                            if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or (adj:GetDistrictType() ~= -1) then
                                obsScore = obsScore + 0.5;
                            end
                        end
                        if obsScore > bestCampusScore then
                            bestCampusScore = obsScore;
                            bestCampus = plot;
                        end
                    else
                        -- Standard Campus
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
            local yieldText = "+" .. cBonus .. " [ICON_Science] Sci";
            if isSeowon then
                yieldText = "+" .. cBonus .. " [ICON_Science] Sci (Seowon โดดเดี่ยว)";
            elseif isObs then
                yieldText = "+" .. cBonus .. " [ICON_Science] Sci (Observatory แปลงเพาะปลูก)";
            end
            table.insert(plannedDistricts, {
                Plot = bestCampus,
                DistrictType = distCampus,
                BaseDistrictType = "DISTRICT_CAMPUS",
                BaseName = Locale.Lookup(GameInfo.Districts[distCampus].Name),
                YieldBonus = yieldText,
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

    -- Step J: Theater Square (Specialty) - Unique District: Acropolis (Greece)
    local bestTheater = nil;
    local isAcrop = (isGreece or distTheater == "DISTRICT_ACROPOLIS");
    if not CityHasDistrict("DISTRICT_THEATER") and GameInfo.Districts[distTheater] ~= nil then
        local bestTSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            -- Acropolis rule: Must be placed on Hills only!
            local isValidTerrain = true;
            if isAcrop and not plot:IsHills() then
                isValidTerrain = false;
            end

            if isValidTerrain and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distTheater, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local tsScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        local isAdjCityCenter = (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) or adj:IsCity();
                        local isAdjDistrict = assignedPlots[adj:GetIndex()] or (adj:GetDistrictType() ~= -1) or isAdjCityCenter;

                        if isAcrop then
                            -- Acropolis Adjacency:
                            -- +1 Culture for each adjacent district (DISTRICT_ALL)
                            -- +1 Culture additional for adjacent City Center (DISTRICT_CITY_CENTER -> total +2)
                            -- +2 Culture for each adjacent Wonder, Entertainment Complex, Water Park, Pamukkale
                            if isAdjCityCenter then
                                tsScore = tsScore + 2; -- +1 district + 1 city center
                            elseif isAdjDistrict then
                                tsScore = tsScore + 1;
                            end

                            if effectiveEntertainmentPlot and adj:GetIndex() == effectiveEntertainmentPlot:GetIndex() then
                                tsScore = tsScore + 2;
                            end
                            local dType = adj:GetDistrictType();
                            if dType ~= -1 and GameInfo.Districts[dType] then
                                local dName = GameInfo.Districts[dType].DistrictType;
                                if dName == "DISTRICT_ENTERTAINMENT_COMPLEX" or dName == "DISTRICT_WATER_ENTERTAINMENT_COMPLEX" or dName == "DISTRICT_WONDER" then
                                    tsScore = tsScore + 2;
                                end
                            end
                            local feat = adj:GetFeatureType();
                            if feat ~= -1 and GameInfo.Features[feat] and (GameInfo.Features[feat].NaturalWonder or GameInfo.Features[feat].FeatureType == "FEATURE_PAMUKKALE") then
                                tsScore = tsScore + 2;
                            end
                        else
                            -- Standard Theater Square Adjacency:
                            -- +2 from Entertainment Complex / Water Park
                            -- +2 from World Wonders / Pamukkale
                            -- +0.5 from each adjacent district (+1 per 2)
                            if effectiveEntertainmentPlot and adj:GetIndex() == effectiveEntertainmentPlot:GetIndex() then
                                tsScore = tsScore + 2;
                            end
                            local dType = adj:GetDistrictType();
                            if dType ~= -1 and GameInfo.Districts[dType] then
                                local dName = GameInfo.Districts[dType].DistrictType;
                                if dName == "DISTRICT_ENTERTAINMENT_COMPLEX" or dName == "DISTRICT_WATER_ENTERTAINMENT_COMPLEX" or dName == "DISTRICT_WONDER" then
                                    tsScore = tsScore + 2;
                                end
                            end
                            local feat = adj:GetFeatureType();
                            if feat ~= -1 and GameInfo.Features[feat] and (GameInfo.Features[feat].NaturalWonder or GameInfo.Features[feat].FeatureType == "FEATURE_PAMUKKALE") then
                                tsScore = tsScore + 2;
                            end
                            if isAdjDistrict then
                                tsScore = tsScore + 0.5;
                            end
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
            local yieldDesc = isAcrop and string.format("+%d [ICON_Culture] Cul (Acropolis เนินเขา)", tsBonus) or string.format("+%d [ICON_Culture] Cul", tsBonus);
            table.insert(plannedDistricts, {
                Plot = bestTheater,
                DistrictType = distTheater,
                BaseDistrictType = "DISTRICT_THEATER",
                BaseName = Locale.Lookup(GameInfo.Districts[distTheater].Name),
                YieldBonus = yieldDesc,
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

    -- Step M: Encampment (Specialty) - Unique District: Thành (Vietnam, Non-specialty)
    local bestEncampment = nil;
    local isThanh = (isVietnam or distEncampment == "DISTRICT_THANH");
    if not CityHasDistrict("DISTRICT_ENCAMPMENT") and GameInfo.Districts[distEncampment] ~= nil then
        local bestEncScore = -1;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);
            -- Thành and Encampment: NoAdjacentCity (dist >= 2) and workable range (dist <= 3)
            local isValidFeature = true;
            if isThanh and not IsValidVietnamFeature(plot) then
                isValidFeature = false;
            end

            if isValidFeature and distFromCity >= 2 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distEncampment, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local minOtherCityDist = 999;
                    for _, oc in ipairs(allCitiesOnMap) do
                        local d = Map.GetPlotDistance(px, py, oc.X, oc.Y);
                        if d < minOtherCityDist then minOtherCityDist = d; end
                    end
                    if minOtherCityDist >= 3 then
                        local encScore = 2;
                        local adjPlots = Map.GetAdjacentPlots(px, py);

                        if isThanh then
                            -- Vietnam Thành: +2 Culture for each adjacent district!
                            local adjDistCount = 0;
                            for _, adj in pairs(adjPlots) do
                                if assignedPlots[adj:GetIndex()] or (adj:GetDistrictType() ~= -1) or adj:IsCity() then
                                    adjDistCount = adjDistCount + 1;
                                end
                            end
                            encScore = (adjDistCount * 4) + (plot:IsHills() and 3 or 0) + 4;
                        else
                            -- Standard Encampment: High defense on hills & border positioning
                            if plot:IsHills() then encScore = encScore + 4; end
                            if minOtherCityDist >= 4 then
                                encScore = encScore + 3; -- Facing wild frontier/borders
                            end
                            for _, adj in pairs(adjPlots) do
                                local rIdx = adj:GetResourceType();
                                if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                                    encScore = encScore + 1;
                                end
                            end
                        end

                        if encScore > bestEncScore then
                            bestEncScore = encScore;
                            bestEncampment = plot;
                        end
                    end
                end
            end
        end
        if bestEncampment ~= nil then
            assignedPlots[bestEncampment:GetIndex()] = true;
            if isThanh then
                local adjDistCount = 0;
                for _, adj in pairs(Map.GetAdjacentPlots(bestEncampment:GetX(), bestEncampment:GetY())) do
                    if assignedPlots[adj:GetIndex()] or (adj:GetDistrictType() ~= -1) or adj:IsCity() then
                        adjDistCount = adjDistCount + 1;
                    end
                end
                local thanhCul = adjDistCount * 2;
                table.insert(plannedDistricts, {
                    Plot = bestEncampment,
                    DistrictType = distEncampment,
                    BaseDistrictType = "DISTRICT_ENCAMPMENT",
                    BaseName = Locale.Lookup(GameInfo.Districts[distEncampment].Name),
                    YieldBonus = string.format("+%d [ICON_Culture] Cul & Defense (Thành ฟรี Pop)", thanhCul),
                    NumericBonus = thanhCul + 2,
                    IsSpecialty = false -- Non-Specialty: does not consume Pop slot!
                });
            else
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

    -- Step P: Spaceport (Non-specialty, strictly Flat Land only, Multi-Factor Scoring)
    -- Civ 6 Engine Rules from civ6_rules/districts/spaceport.md:
    -- 1. Non-Specialty: RequiresPopulation = false (does not consume city district quota)
    -- 2. NoAdjacentCity = false: CAN be built in Ring 1 adjacent to City Center! Workable range 1-3.
    -- 3. Strictly Flat Land only: Desert, Grass, Plains, Snow, Tundra (No Hills, No Mountain, No Water, No Impassable, No Ice, No Natural Wonder)
    -- 4. Resource Constraints: Cannot crush Luxury or revealed Strategic. Bonus resources only if harvest tech unlocked.
    -- 5. Science Victory Quota: Allow up to 3 Spaceports empire-wide across top-tier production cities for laser project acceleration.
    local bestSpaceport = nil;
    local empireSpaceportCount = CountEmpireSpaceports(playerID);
    local qualifiesForSpaceport = false;

    -- City production gating: Spaceport costs 1800 base production. Only cities with real industrial capacity qualify.
    if effectiveIZPlot ~= nil or CityHasDistrict("DISTRICT_INDUSTRIAL_ZONE") then
        qualifiesForSpaceport = true;
    elseif isCapital then
        qualifiesForSpaceport = true;
    elseif pCity ~= nil and pCity:GetPopulation() >= 8 then
        qualifiesForSpaceport = true;
    end

    if qualifiesForSpaceport and empireSpaceportCount < 3 and not CityHasDistrict("DISTRICT_SPACEPORT") and GameInfo.Districts[distSpaceport] ~= nil then
        local bestSpaceScore = -999;
        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);

            -- Valid range 1 to 3 hexes; strictly Flat Land (No Hills, Mountain, Water, Impassable)
            if distFromCity >= 1 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() and not plot:IsHills() and not plot:IsImpassable() then
                local tIdx = plot:GetTerrainType();
                local isTerrainValid = false;
                if tIdx ~= -1 and GameInfo.Terrains[tIdx] ~= nil then
                    local tType = GameInfo.Terrains[tIdx].TerrainType;
                    if tType == "TERRAIN_DESERT" or tType == "TERRAIN_GRASS" or tType == "TERRAIN_PLAINS" or tType == "TERRAIN_SNOW" or tType == "TERRAIN_TUNDRA" then
                        isTerrainValid = true;
                    end
                end

                local fIdx = plot:GetFeatureType();
                local isFeatureForbidden = false;
                if fIdx ~= -1 and GameInfo.Features[fIdx] ~= nil then
                    local fType = GameInfo.Features[fIdx].FeatureType;
                    if fType == "FEATURE_ICE" or GameInfo.Features[fIdx].NaturalWonder then
                        isFeatureForbidden = true;
                    end
                end

                if isTerrainValid and not isFeatureForbidden and not HasForbiddenResourceForDistrict(playerID, plot) then
                    local pinSub = { X = px, Y = py, Key = distSpaceport, Type = MAP_PIN_TYPES.DISTRICT };
                    if CanPlacePin(playerID, pinSub) then
                        local spaceScore = 10;

                        -- 1. Spy Protection & Counterspy Radius:
                        -- Ring 1 is directly protected by City Center garrison, walls strike, and Counterspy in City Center!
                        if distFromCity == 1 then
                            spaceScore = spaceScore + 8;
                        elseif distFromCity == 2 then
                            spaceScore = spaceScore + 5;
                        else
                            spaceScore = spaceScore + 1;
                        end

                        -- 2. Industrial Zone Synergy (Production core & Great Engineer transit)
                        if effectiveIZPlot ~= nil then
                            local dToIZ = Map.GetPlotDistance(px, py, effectiveIZPlot:GetX(), effectiveIZPlot:GetY());
                            if dToIZ == 1 then
                                spaceScore = spaceScore + 6;
                            elseif dToIZ == 2 then
                                spaceScore = spaceScore + 2;
                            end
                        end

                        -- 3. Diplomatic Quarter / Government Plaza Proximity (Counterspy defense cluster)
                        if effectiveDiploQuarterPlot ~= nil and Map.GetPlotDistance(px, py, effectiveDiploQuarterPlot:GetX(), effectiveDiploQuarterPlot:GetY()) == 1 then
                            spaceScore = spaceScore + 3;
                        end
                        if effectiveGovPlazaPlot ~= nil and Map.GetPlotDistance(px, py, effectiveGovPlazaPlot:GetX(), effectiveGovPlazaPlot:GetY()) == 1 then
                            spaceScore = spaceScore + 2;
                        end

                        -- 4. Tactical Safety from Hostile Borders & Pillage Raids
                        local minDistToForeignCity = 999;
                        for _, oc in ipairs(allCitiesOnMap) do
                            if not oc.IsSamePlayer then
                                local d = Map.GetPlotDistance(px, py, oc.X, oc.Y);
                                if d < minDistToForeignCity then
                                    minDistToForeignCity = d;
                                end
                            end
                        end
                        if minDistToForeignCity <= 3 then
                            spaceScore = spaceScore - 12; -- Dangerously close to enemy frontlines
                        elseif minDistToForeignCity <= 5 then
                            spaceScore = spaceScore - 6;
                        elseif minDistToForeignCity >= 8 then
                            spaceScore = spaceScore + 4;  -- Deep safe interior
                        end

                        -- 5. Coastal Vulnerability Check (Naval Raider Pillaging)
                        local adjPlots = Map.GetAdjacentPlots(px, py);
                        local isCoastalExposed = false;
                        local mountainHillsShield = 0;
                        for _, adj in pairs(adjPlots) do
                            if adj:IsWater() and not adj:IsLake() then
                                isCoastalExposed = true;
                            end
                            if adj:IsMountain() or adj:IsHills() then
                                mountainHillsShield = mountainHillsShield + 1;
                            end
                        end
                        if isCoastalExposed then
                            spaceScore = spaceScore - 4; -- Coastline spaceports risk naval bombardment
                        end
                        if mountainHillsShield >= 2 then
                            spaceScore = spaceScore + 3;
                        elseif mountainHillsShield == 1 then
                            spaceScore = spaceScore + 1;
                        end

                        -- 6. Preserve Protection (Spaceport reduces Appeal by -1)
                        local existingPreserve = GetExistingDistrictPlot("DISTRICT_PRESERVE");
                        if existingPreserve ~= nil and Map.GetPlotDistance(px, py, existingPreserve:GetX(), existingPreserve:GetY()) == 1 then
                            spaceScore = spaceScore - 8;
                        end

                        -- 7. Low-Yield Land Efficiency (Barren flat desert/snow/tundra is ideal)
                        if tIdx ~= -1 and GameInfo.Terrains[tIdx] ~= nil then
                            local tType = GameInfo.Terrains[tIdx].TerrainType;
                            if tType == "TERRAIN_DESERT" or tType == "TERRAIN_SNOW" or tType == "TERRAIN_TUNDRA" then
                                spaceScore = spaceScore + 4;
                            end
                        end

                        if spaceScore > bestSpaceScore then
                            bestSpaceScore = spaceScore;
                            bestSpaceport = plot;
                        end
                    end
                end
            end
        end
        if bestSpaceport ~= nil then
            assignedPlots[bestSpaceport:GetIndex()] = true;
            local numBonus = math.max(1, math.floor(bestSpaceScore / 3));
            table.insert(plannedDistricts, {
                Plot = bestSpaceport,
                DistrictType = distSpaceport,
                BaseDistrictType = "DISTRICT_SPACEPORT",
                BaseName = Locale.Lookup(GameInfo.Districts[distSpaceport].Name),
                YieldBonus = "Science Victory (โครงการอวกาศ)",
                NumericBonus = numBonus,
                IsSpecialty = false
            });
        end
    end
    local effectiveSpaceportPlot = bestSpaceport or GetExistingDistrictPlot("DISTRICT_SPACEPORT");

    -- Step Q: Preserve (Specialty, NoAdjacentCity: dist >= 2, High Appeal / Nature synergy)
    local bestPreserve = nil;
    if not CityHasDistrict("DISTRICT_PRESERVE") and GameInfo.Districts[distPreserve] ~= nil then
        local bestPreserveScore = -999;
        local bestPreserveHousing = 1;
        local bestPreserveAppeal = 0;
        local bestPreserveAdjHigh = 0;

        for _, plot in ipairs(candidatePlots) do
            local px, py = plot:GetX(), plot:GetY();
            local distFromCity = Map.GetPlotDistance(cityX, cityY, px, py);

            -- Preserve rule: NoAdjacentCity (dist >= 2) and within workable territory (dist <= 3)
            if distFromCity >= 2 and distFromCity <= 3 and IsPlotAvailable(plot, false) and not plot:IsWater() and not plot:IsMountain() then
                local pinSub = { X = px, Y = py, Key = distPreserve, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local appeal = plot:GetAppeal();
                    local housing = (appeal >= 4) and 3 or ((appeal >= 2) and 2 or 1);
                    local preserveScore = housing * 5;
                    local adjHighCount = 0;

                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        local adjAppeal = adj:GetAppeal();
                        local fIdx = adj:GetFeatureType();
                        local isNatWonder = (fIdx ~= -1 and GameInfo.Features[fIdx] and GameInfo.Features[fIdx].NaturalWonder);

                        if adj:IsMountain() or isNatWonder then
                            preserveScore = preserveScore + 6; -- Mountain/Natural Wonder is permanently pristine unimproved tile
                            adjHighCount = adjHighCount + 1;
                        elseif adj:IsWater() then
                            preserveScore = preserveScore + 2; -- Coast/Lake provides appeal
                        elseif adjAppeal >= 4 then
                            preserveScore = preserveScore + 4; -- Breathtaking neighbor for Grove/Sanctuary
                            adjHighCount = adjHighCount + 1;
                        elseif adjAppeal >= 2 then
                            preserveScore = preserveScore + 2; -- Charming neighbor
                            adjHighCount = adjHighCount + 1;
                        end

                        -- Penalize adjacency to heavy industry or other planned districts (reduces unimproved nature tiles)
                        if assignedPlots[adj:GetIndex()] or (adj:GetDistrictType() ~= -1) then
                            preserveScore = preserveScore - 2;
                        end
                        if effectiveSpaceportPlot ~= nil and adj:GetIndex() == effectiveSpaceportPlot:GetIndex() then
                            preserveScore = preserveScore - 3; -- Spaceport reduces appeal
                        end
                    end

                    if preserveScore > bestPreserveScore then
                        bestPreserveScore = preserveScore;
                        bestPreserveHousing = housing;
                        bestPreserveAppeal = appeal;
                        bestPreserveAdjHigh = adjHighCount;
                        bestPreserve = plot;
                    end
                end
            end
        end

        if bestPreserve ~= nil then
            assignedPlots[bestPreserve:GetIndex()] = true;
            local yieldText = string.format("+%d Housing (Appeal %d, บัฟ %d ช่อง)", bestPreserveHousing, bestPreserveAppeal, bestPreserveAdjHigh);
            table.insert(plannedDistricts, {
                Plot = bestPreserve,
                DistrictType = distPreserve,
                BaseDistrictType = "DISTRICT_PRESERVE",
                BaseName = Locale.Lookup(GameInfo.Districts[distPreserve].Name),
                YieldBonus = yieldText,
                NumericBonus = bestPreserveHousing + bestPreserveAdjHigh,
                IsSpecialty = true
            });
        end
    end
    local effectivePreservePlot = bestPreserve or GetExistingDistrictPlot("DISTRICT_PRESERVE");

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
        UpdateSmartPlannerContextVisibility();
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

    local sortedReplanCities = {};
    for _, cityInfo in pairs(replanCities) do
        table.insert(sortedReplanCities, cityInfo);
    end
    table.sort(sortedReplanCities, function(a, b)
        local pCityA = CityManager and CityManager.GetCityAt and CityManager.GetCityAt(a.CityX, a.CityY);
        local pCityB = CityManager and CityManager.GetCityAt and CityManager.GetCityAt(b.CityX, b.CityY);
        local isCapA = pCityA and pCityA.IsCapital and pCityA:IsCapital() or false;
        local isCapB = pCityB and pCityB.IsCapital and pCityB:IsCapital() or false;
        if isCapA and not isCapB then return true; end
        if not isCapA and isCapB then return false; end
        return false;
    end);

    for _, cityInfo in ipairs(sortedReplanCities) do
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
            UpdateSmartPlannerContextVisibility();
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
            UpdateSmartPlannerContextVisibility();
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

    local pPlayer = Players[ownerPlayerID];
    if not pPlayer then return; end
    local pCities = pPlayer:GetCities();
    if not pCities then return; end

    local capital = pCities:GetCapitalCity();
    -- Requirement 2: Always calculate / ensure Capital districts are planned first!
    if capital ~= nil and (capital:GetX() ~= cityX or capital:GetY() ~= cityY) then
        print(string.format("DMT: New secondary city at (%d, %d). Ensuring Capital [%s] at (%d, %d) is prioritized and optimized first!",
            cityX, cityY, Locale.Lookup(capital:GetName()), capital:GetX(), capital:GetY()));
        OptimizeCityDistricts(ownerPlayerID, capital:GetX(), capital:GetY(), capital:GetID(), false);
    end

    OptimizeCityDistricts(ownerPlayerID, cityX, cityY, cityID, false);
end

function DMT_OnCitySelectionChanged(owner, cityID, i, j, k, bSelected, bEditable)
    if owner ~= Game.GetLocalPlayer() then return; end
    if not bSelected then
        if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
            Controls.CityDistrictPlanPanel:SetHide(true);
            UpdateSmartPlannerContextVisibility();
        end
    end
end

-- =======================================================================
-- Initialization & Dynamic Context Visibility
-- =======================================================================
local m_SmartPlannerInitialized = false;

function DMT_SmartPlanner_Initialize()
    if m_SmartPlannerInitialized then return; end
    m_SmartPlannerInitialized = true;

    EnsureInstanceManagers();

    -- Ensure Context is hidden by default so it never captures mouse clicks or hit-tests
    UpdateSmartPlannerContextVisibility();

    Events.UnitSelectionChanged.Add(DMT_OnUnitSelectionChanged);
    Events.UnitMoveComplete.Add(DMT_OnUnitMoveComplete);
    Events.CityAddedToMap.Add(DMT_OnCityAddedToMap);
    Events.CitySelectionChanged.Add(DMT_OnCitySelectionChanged);
    Events.LocalPlayerTurnEnd.Add(function()
        if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
            Controls.CityDistrictPlanPanel:SetHide(true);
        end
        if Controls.SettlerRecommendationPanel and not Controls.SettlerRecommendationPanel:IsHidden() then
            Controls.SettlerRecommendationPanel:SetHide(true);
        end
        UpdateSmartPlannerContextVisibility();
    end);

    if LuaEvents.ProductionPanel_Open then
        LuaEvents.ProductionPanel_Open.Add(function()
            if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
                Controls.CityDistrictPlanPanel:SetHide(true);
                UpdateSmartPlannerContextVisibility();
            end
        end);
    end
    if LuaEvents.CityPanel_ProductionOpen then
        LuaEvents.CityPanel_ProductionOpen.Add(function()
            if Controls.CityDistrictPlanPanel and not Controls.CityDistrictPlanPanel:IsHidden() then
                Controls.CityDistrictPlanPanel:SetHide(true);
                UpdateSmartPlannerContextVisibility();
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
