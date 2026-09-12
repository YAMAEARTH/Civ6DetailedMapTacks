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
    return m_AutoDistrictPins[x .. "_" .. y] == true;
end

-- Safely look up any pin that actually exists on the map from PlayerConfigurations
local function GetPinAtPlot(playerCfg, px, py)
    if not playerCfg then return nil; end
    local allPins = playerCfg:GetMapPins();
    if allPins ~= nil then
        for _, pin in pairs(allPins) do
            if pin:GetHexX() == px and pin:GetHexY() == py then
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
            if not name:match("^#%d.*ตั้งเมือง") then
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
    if allPins ~= nil then
        for pinID, pin in pairs(allPins) do
            local px, py = pin:GetHexX(), pin:GetHexY();
            local key = px .. "_" .. py;
            local pinName = pin:GetName() or "";
            if m_AutoSettlerPins[key] or pinName:match("^#%d.*ตั้งเมือง") then
                LuaEvents.DMT_MapPinRemoved(pin);
                playerCfg:DeleteMapPin(pinID);
                m_AutoSettlerPins[key] = nil;
                hasChanges = true;
            end
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

function ScoreSettlerPlot(playerID, pPlot, settlerX, settlerY, grandAIPlots)
    local score = 0;
    local px, py = pPlot:GetX(), pPlot:GetY();
    local reasons = {};
    local waterTag = "ไม่มีน้ำ (2 Housing)";

    -- 1. Water & Housing
    if pPlot:IsFreshWater() then
        score = score + 26;
        waterTag = "น้ำจืด (+3 Housing)";
        table.insert(reasons, "แหล่งน้ำจืด");
    elseif pPlot:IsCoastalLand() then
        score = score + 12;
        waterTag = "ชายฝั่ง (+1 Housing)";
        table.insert(reasons, "ติดชายฝั่ง");
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
    local searchPlots = GetPlotsWithinXTiles(settlerX, settlerY, 5);
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
                table.insert(candidates, {
                    Plot = plot,
                    Score = score,
                    WaterTag = waterTag,
                    Reasons = reasons
                });
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
    if allPins ~= nil then
        for pinID, pin in pairs(allPins) do
            local px, py = pin:GetHexX(), pin:GetHexY();
            local key = px .. "_" .. py;
            if cityPlotSet[key] and m_AutoDistrictPins[key] then
                LuaEvents.DMT_MapPinRemoved(pin);
                playerCfg:DeleteMapPin(pinID);
                m_AutoDistrictPins[key] = nil;
                hasChanges = true;
            end
        end
    end

    if hasChanges then
        Network.BroadcastPlayerInfo();
        LuaEvents.DMT_RefreshMapPins();
    end
end

function OptimizeCityDistricts(playerID, cityX, cityY)
    if playerID ~= Game.GetLocalPlayer() then return; end
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    EnsureInstanceManagers();

    print(string.format("DMT Smart Planner: Optimizing districts for city at (%d, %d)", cityX, cityY));

    ClearAutoSettlerPins(playerID);
    if Controls.SettlerRecommendationPanel then
        Controls.SettlerRecommendationPanel:SetHide(true);
    end

    local allCityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local candidatePlots = {};
    local occupiedPlots = {};

    occupiedPlots[Map.GetPlot(cityX, cityY):GetIndex()] = true;

    for _, plot in ipairs(allCityPlots) do
        local pIdx = plot:GetIndex();
        local px, py = plot:GetX(), plot:GetY();

        local hasExistingDistrict = plot:GetDistrictType() ~= -1 or plot:IsCity();
        local isForeignOwned = plot:IsOwned() and plot:GetOwner() ~= playerID;
        local isImpassable = plot:IsImpassable() or not IsPlotVisibleOrRevealed(plot, playerID);
        local hasManualPin = HasManualPinAtPlot(playerCfg, px, py);

        if hasExistingDistrict or isForeignOwned or isImpassable or hasManualPin then
            occupiedPlots[pIdx] = true;
        else
            table.insert(candidatePlots, plot);
        end
    end

    local distAqueduct   = GetPlayerUniqueDistrict(playerID, "DISTRICT_AQUEDUCT");
    local distDam        = GetPlayerUniqueDistrict(playerID, "DISTRICT_DAM");
    local distIZ         = GetPlayerUniqueDistrict(playerID, "DISTRICT_INDUSTRIAL_ZONE");
    local distCommHub    = GetPlayerUniqueDistrict(playerID, "DISTRICT_COMMERCIAL_HUB");
    local distHarbor     = GetPlayerUniqueDistrict(playerID, "DISTRICT_HARBOR");
    local distCampus     = GetPlayerUniqueDistrict(playerID, "DISTRICT_CAMPUS");
    local distHolySite   = GetPlayerUniqueDistrict(playerID, "DISTRICT_HOLY_SITE");
    local distTheater    = GetPlayerUniqueDistrict(playerID, "DISTRICT_THEATER");
    local distGovPlaza   = GetPlayerUniqueDistrict(playerID, "DISTRICT_GOVERNMENT");

    local plannedDistricts = {};
    local assignedPlots = {};

    local function IsPlotAvailable(plot)
        return plot ~= nil and not occupiedPlots[plot:GetIndex()] and not assignedPlots[plot:GetIndex()];
    end

    -- Step A: Aqueduct
    local bestAqueduct = nil;
    if GameInfo.Districts[distAqueduct] ~= nil then
        local bestAqueductScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidAqueductPosition(playerID, px, py) then
                    local score = 10;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if IsPlotAvailable(adj) and not adj:IsWater() and not adj:IsMountain() then
                            score = score + 5;
                        end
                    end
                    if score > bestAqueductScore then
                        bestAqueductScore = score;
                        bestAqueduct = plot;
                    end
                end
            end
        end
        if bestAqueduct ~= nil then
            assignedPlots[bestAqueduct:GetIndex()] = true;
            table.insert(plannedDistricts, {
                Plot = bestAqueduct,
                DistrictType = distAqueduct,
                BaseName = Locale.Lookup(GameInfo.Districts[distAqueduct].Name),
                YieldBonus = "+2 Housing"
            });
        end
    end

    -- Step B: Dam
    local bestDam = nil;
    if GameInfo.Districts[distDam] ~= nil then
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidDamPosition(playerID, px, py) then
                    bestDam = plot;
                    assignedPlots[plot:GetIndex()] = true;
                    table.insert(plannedDistricts, {
                        Plot = plot,
                        DistrictType = distDam,
                        BaseName = Locale.Lookup(GameInfo.Districts[distDam].Name),
                        YieldBonus = "+3 Housing & Power"
                    });
                    break;
                end
            end
        end
    end

    -- Step C: Industrial Zone
    local bestIZ = nil;
    if GameInfo.Districts[distIZ] ~= nil then
        local bestIZScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distIZ, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local izScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if bestAqueduct and adj:GetIndex() == bestAqueduct:GetIndex() then
                            izScore = izScore + 2;
                        end
                        if bestDam and adj:GetIndex() == bestDam:GetIndex() then
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
                BaseName = Locale.Lookup(GameInfo.Districts[distIZ].Name),
                YieldBonus = "+" .. izBonus .. " [ICON_Production] Prod"
            });
        end
    end

    -- Step D: Harbor
    local bestHarbor = nil;
    if GameInfo.Districts[distHarbor] ~= nil then
        local bestHarborScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and plot:IsWater() then
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
            table.insert(plannedDistricts, {
                Plot = bestHarbor,
                DistrictType = distHarbor,
                BaseName = Locale.Lookup(GameInfo.Districts[distHarbor].Name),
                YieldBonus = "+" .. math.max(2, bestHarborScore) .. " [ICON_Gold] Gold"
            });
        end
    end

    -- Step E: Commercial Hub
    local bestCommHub = nil;
    if GameInfo.Districts[distCommHub] ~= nil then
        local bestCHScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCommHub, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local chScore = 0;
                    if plot:IsRiver() then chScore = chScore + 2; end
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if bestHarbor and adj:GetIndex() == bestHarbor:GetIndex() then
                            chScore = chScore + 2;
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) then
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
                BaseName = Locale.Lookup(GameInfo.Districts[distCommHub].Name),
                YieldBonus = "+" .. chBonus .. " [ICON_Gold] Gold"
            });
        end
    end

    -- Step F: Campus
    local bestCampus = nil;
    if GameInfo.Districts[distCampus] ~= nil then
        local bestCampusScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCampus, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
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
                        if assignedPlots[adj:GetIndex()] then cScore = cScore + 0.5; end
                    end
                    if cScore > bestCampusScore then
                        bestCampusScore = cScore;
                        bestCampus = plot;
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
                BaseName = Locale.Lookup(GameInfo.Districts[distCampus].Name),
                YieldBonus = "+" .. cBonus .. " [ICON_Science] Sci"
            });
        end
    end

    -- Step G: Holy Site
    local bestHolySite = nil;
    if GameInfo.Districts[distHolySite] ~= nil then
        local bestHSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
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
                        if assignedPlots[adj:GetIndex()] then hsScore = hsScore + 0.5; end
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
                BaseName = Locale.Lookup(GameInfo.Districts[distHolySite].Name),
                YieldBonus = "+" .. hsBonus .. " [ICON_Faith] Faith"
            });
        end
    end

    -- Step H: Theater Square
    local bestTheater = nil;
    if GameInfo.Districts[distTheater] ~= nil then
        local bestTSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distTheater, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local tsScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if assignedPlots[adj:GetIndex()] then
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
                BaseName = Locale.Lookup(GameInfo.Districts[distTheater].Name),
                YieldBonus = "+" .. tsBonus .. " [ICON_Culture] Cul"
            });
        end
    end

    -- Step I: Government Plaza
    if GameInfo.Districts[distGovPlaza] ~= nil and not HasEmpireGovernmentPlaza(playerID) then
        local bestGov = nil;
        local bestGovScore = 2;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distGovPlaza, Type = MAP_PIN_TYPES.DISTRICT };
                if CanPlacePin(playerID, pinSub) then
                    local touchingCount = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if assignedPlots[adj:GetIndex()] then
                            touchingCount = touchingCount + 1;
                        end
                    end
                    if touchingCount > bestGovScore then
                        bestGovScore = touchingCount;
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
                BaseName = Locale.Lookup(GameInfo.Districts[distGovPlaza].Name),
                YieldBonus = "+" .. bestGovScore .. " All Adj"
            });
        end
    end

    -- Populate HUD UI Panel & Place World Map Pins
    if m_DistrictIM ~= nil then
        m_DistrictIM:ResetInstances();
    end

    local pinsToUpdate = {};
    for _, item in ipairs(plannedDistricts) do
        local px, py = item.Plot:GetX(), item.Plot:GetY();
        local pinName = string.format("%s (%s)", item.BaseName, item.YieldBonus);
        local iconName = "ICON_" .. item.DistrictType;

        -- 1. Populate HUD UI list
        if m_DistrictIM ~= nil then
            local uiEntry = m_DistrictIM:GetInstance();
            uiEntry.DistrictIcon:SetIcon(iconName);
            uiEntry.DistrictNameLabel:SetText(item.BaseName);
            uiEntry.DistrictBonusLabel:SetText(item.YieldBonus);
        end

        -- 2. Place Map Pin on World Map
        if not HasManualPinAtPlot(playerCfg, px, py) then
            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                pin:SetName(pinName);
                pin:SetIconName(iconName);
                pin:SetVisibility(playerID);

                m_AutoDistrictPins[px .. "_" .. py] = true;

                local pinSubject = CreateMapPinSubject(pin);
                table.insert(pinsToUpdate, pinSubject);
            end
        end
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
            Controls.CityNameLabel:SetText(string.format("วางแผนเขตเมืองสำเร็จ (%d เขต):", #plannedDistricts));
        end
        if Controls.LookAtCityButton then
            Controls.LookAtCityButton:RegisterCallback(Mouse.eLClick, function()
                UI.LookAtPlot(cityX, cityY);
            end);
        end
    end

    UI.PlaySound("Map_Pin_Add");
    print(string.format("DMT Smart Planner: Successfully displayed UI and placed %d district pins for city!", #plannedDistricts));
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
        OptimizeCityDistricts(playerID, pSelectedCity:GetX(), pSelectedCity:GetY());
        return;
    end

    -- 3. Check cursor plot
    local cursorX, cursorY = UI.GetCursorPlotCoord();
    local cursorPlot = Map.GetPlot(cursorX, cursorY);
    if cursorPlot ~= nil then
        if cursorPlot:IsCity() then
            print("DMT Hotkey: Triggering District Optimization for city under cursor");
            OptimizeCityDistricts(playerID, cursorX, cursorY);
            return;
        end
        local owningCity = (Cities and Cities.GetPlotPurchaseCity) and Cities.GetPlotPurchaseCity(cursorPlot) or nil;
        if owningCity ~= nil and owningCity:GetOwner() == playerID then
            print("DMT Hotkey: Triggering District Optimization for owning city: " .. Locale.Lookup(owningCity:GetName()));
            UI.SelectCity(owningCity);
            OptimizeCityDistricts(playerID, owningCity:GetX(), owningCity:GetY());
            return;
        end
        local cityAt = CityManager.GetCityAt(cursorX, cursorY);
        if cityAt ~= nil and cityAt:GetOwner() == playerID then
            print("DMT Hotkey: Triggering District Optimization for city at cursor plot");
            OptimizeCityDistricts(playerID, cityAt:GetX(), cityAt:GetY());
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
            OptimizeCityDistricts(playerID, capital:GetX(), capital:GetY());
            return;
        end
        for i, city in pCities:Members() do
            print("DMT Hotkey: Fallback to City District Optimization");
            UI.SelectCity(city);
            UI.LookAtPlot(city:GetX(), city:GetY());
            OptimizeCityDistricts(playerID, city:GetX(), city:GetY());
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
    OptimizeCityDistricts(ownerPlayerID, cityX, cityY);
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

    -- Hotkey Listener for SHIFT + A & Close Panels
    LuaEvents.DMT_TriggerSmartPlannerHotkey.Add(OnTriggerSmartPlannerHotkey);
    LuaEvents.DMT_ClosePanels.Add(function()
        OnCloseSettlerPanel();
        OnCloseDistrictPanel();
    end);

    LuaEvents.DMT_PlanDistrictsForCity.Add(OptimizeCityDistricts);
    LuaEvents.DMT_ClearAutoDistricts.Add(ClearAutoDistrictsForCity);

    print("DMT Smart Planner initialized with HUD UI & SHIFT+A hotkey successfully.");
end
