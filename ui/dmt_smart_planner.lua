-- =======================================================================
-- DMT Smart Planner: Settler Recommendations & City District Optimizer
-- Author: YAMAEARTH / Antigravity
-- Pure client-side UI script (Single player & Multiplayer safe)
-- =======================================================================

print("Loading DMT_SmartPlanner.lua");

include("civ6common");
include("MapTacks");

-- Cache of auto-placed pins so we never overwrite player manual pins
local m_AutoSettlerPins = {};
local m_AutoDistrictPins = {};
local m_LastSettlerUnitID = -1;
local m_LastSettlerPlotIndex = -1;

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

-- Check if a plot coordinate is an auto-placed settler pin
local function IsAutoSettlerPin(x, y)
    return m_AutoSettlerPins[x .. "_" .. y] == true;
end

-- Check if a plot coordinate is an auto-placed district pin
local function IsAutoDistrictPin(x, y)
    return m_AutoDistrictPins[x .. "_" .. y] == true;
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

-- Check if the player already built or queued a Government Plaza anywhere
function HasEmpireGovernmentPlaza(playerID)
    local pPlayer = Players[playerID];
    if not pPlayer then return false; end
    local pCities = pPlayer:GetCities();
    for i, pCity in pCities:Members() do
        local pCityDistricts = pCity:GetDistricts();
        for district in pCityDistricts:Members() do
            local districtType = GameInfo.Districts[district:GetType()].DistrictType;
            if districtType == "DISTRICT_GOVERNMENT" then
                return true;
            end
        end
    end
    return false;
end

-- =======================================================================
-- Settler Recommendation & Top 3 Placement
-- =======================================================================

-- Clear previously placed auto settler pins
function ClearAutoSettlerPins(playerID)
    if playerID == nil or playerID ~= Game.GetLocalPlayer() then
        playerID = Game.GetLocalPlayer();
    end
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local hasChanges = false;
    for key, _ in pairs(m_AutoSettlerPins) do
        local parts = {};
        for part in string.gmatch(key, "([^_-]+)") do
            table.insert(parts, tonumber(part));
        end
        if #parts == 2 then
            local px, py = parts[1], parts[2];
            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                local pinName = pin:GetName() or "";
                if pinName:match("^#%d Settle") then
                    LuaEvents.DMT_MapPinRemoved(pin);
                    playerCfg:DeleteMapPin(pin:GetID());
                    hasChanges = true;
                end
            end
        end
    end
    m_AutoSettlerPins = {};

    if hasChanges then
        Network.BroadcastPlayerInfo();
    end
end

-- Check if a plot is a valid location for settling a city
function IsValidCitySettlePlot(playerID, pPlot)
    if pPlot == nil then return false; end
    if not pPlot:IsRevealed(playerID) then return false; end
    if pPlot:IsWater() then return false; end
    if pPlot:IsImpassable() then return false; end
    if pPlot:IsMountain() then return false; end
    if pPlot:IsCity() then return false; end

    -- Check if territory is owned by another civilization
    if pPlot:IsOwned() and pPlot:GetOwner() ~= playerID then
        return false;
    end

    local px, py = pPlot:GetX(), pPlot:GetY();

    -- Minimum distance from any existing city (Base Civ 6 rule: 3 tiles radius, min distance 4)
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

-- Calculate Settler Score for a candidate plot
function ScoreSettlerPlot(playerID, pPlot, settlerX, settlerY, grandAIPlots)
    local score = 0;
    local px, py = pPlot:GetX(), pPlot:GetY();
    local reasons = {};

    -- 1. Fresh Water & Housing
    if pPlot:IsFreshWater() then
        score = score + 26;
        table.insert(reasons, "Fresh Water (+3 Housing)");
    elseif pPlot:IsCoastalLand() then
        score = score + 12;
        table.insert(reasons, "Coastal (+1 Housing)");
    else
        score = score + 0;
        table.insert(reasons, "No Fresh Water");
    end

    -- 2. City Center Tile Quality
    local terrainIndex = pPlot:GetTerrainType();
    local terrainInfo = GameInfo.Terrains[terrainIndex];
    local isPlainsHills = false;
    if terrainInfo ~= nil and terrainInfo.Hills then
        if terrainInfo.TerrainType == "TERRAIN_PLAINS_HILLS" then
            isPlainsHills = true;
            score = score + 12; -- 2 Food / 2 Prod free base + 3 combat strength
            table.insert(reasons, "Plains Hills (+1 Prod base & Defense)");
        else
            score = score + 5;
            table.insert(reasons, "Hills (+3 Defense)");
        end
    end

    local resIndex = pPlot:GetResourceType();
    if resIndex ~= -1 then
        local resInfo = GameInfo.Resources[resIndex];
        if resInfo ~= nil then
            if resInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                score = score + 8;
                table.insert(reasons, "Luxury on Settle: " .. Locale.Lookup(resInfo.Name));
            elseif resInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                score = score + 6;
                table.insert(reasons, "Strategic on Settle: " .. Locale.Lookup(resInfo.Name));
            end
        end
    end

    -- 3. Ring 1 Plots Evaluation (6 hexes)
    local ring1Plots = Map.GetAdjacentPlots(px, py);
    local ring1Food, ring1Prod, ring1Luxuries = 0, 0, 0;
    for _, adjPlot in pairs(ring1Plots) do
        if adjPlot ~= nil and adjPlot:IsRevealed(playerID) and not adjPlot:IsImpassable() then
            -- Yields
            local f = adjPlot:GetYield(GameInfo.Yields["YIELD_FOOD"].Index);
            local p = adjPlot:GetYield(GameInfo.Yields["YIELD_PRODUCTION"].Index);
            local g = adjPlot:GetYield(GameInfo.Yields["YIELD_GOLD"].Index);
            local s = adjPlot:GetYield(GameInfo.Yields["YIELD_SCIENCE"].Index);
            local c = adjPlot:GetYield(GameInfo.Yields["YIELD_CULTURE"].Index);
            local faith = adjPlot:GetYield(GameInfo.Yields["YIELD_FAITH"].Index);

            -- High yield tile bonus
            if f >= 3 then score = score + 5; else score = score + (f * 1.5); end
            if p >= 2 then score = score + 6; else score = score + (p * 2.0); end
            score = score + (s * 2.5) + (c * 2.5) + (faith * 2.0) + (g * 0.5);

            -- Resources
            local rIndex = adjPlot:GetResourceType();
            if rIndex ~= -1 then
                local rInfo = GameInfo.Resources[rIndex];
                if rInfo ~= nil then
                    if rInfo.ResourceClassType == "RESOURCECLASS_LUXURY" then
                        score = score + 7;
                        ring1Luxuries = ring1Luxuries + 1;
                    elseif rInfo.ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                        score = score + 5;
                    else
                        score = score + 3; -- Bonus resource
                    end
                end
            end

            -- Features / Chops / Wonders
            local featIndex = adjPlot:GetFeatureType();
            if featIndex ~= -1 then
                local featInfo = GameInfo.Features[featIndex];
                if featInfo ~= nil then
                    if featInfo.NaturalWonder then
                        score = score + 14;
                    elseif featInfo.FeatureType == "FEATURE_GEOTHERMAL_FISSURE" or featInfo.FeatureType == "FEATURE_REEF" then
                        score = score + 4;
                    elseif featInfo.FeatureType == "FEATURE_FOREST" or featInfo.FeatureType == "FEATURE_JUNGLE" or featInfo.FeatureType == "FEATURE_MARSH" then
                        score = score + 2; -- Choppable
                    end
                end
            end

            -- Mountain adjacency for future Campus/Holy Site
            if adjPlot:IsMountain() then
                score = score + 2.5;
            end
        end
    end

    -- 4. Ring 2 Plots Evaluation (12 hexes)
    local allWithin2 = GetPlotsWithinXTiles(px, py, 2);
    for _, plot2 in ipairs(allWithin2) do
        local dist = Map.GetPlotDistance(px, py, plot2:GetX(), plot2:GetY());
        if dist == 2 and plot2:IsRevealed(playerID) and not plot2:IsImpassable() then
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

    -- 5. Movement Distance Penalty from Settler
    local moveDist = Map.GetPlotDistance(settlerX, settlerY, px, py);
    if moveDist == 0 then
        score = score + 0; -- Settle immediately!
    elseif moveDist == 1 then
        score = score - 2; -- 1 turn move
    elseif moveDist == 2 then
        score = score - 5;
    elseif moveDist == 3 then
        score = score - 9;
    else
        score = score - (9 + (moveDist - 3) * 4);
    end

    -- 6. Firaxis Strategic AI Recommendation Bonus
    if grandAIPlots[pPlot:GetIndex()] then
        score = score + 10;
        table.insert(reasons, "AI Recommended");
    end

    return math.floor(score + 0.5), reasons;
end

-- Recommend Top 3 Settler spots and place map pins
function RecommendSettlerSpots(playerID, pUnit)
    if playerID ~= Game.GetLocalPlayer() then return; end
    if pUnit == nil then return; end

    local settlerX, settlerY = pUnit:GetX(), pUnit:GetY();
    local settlerPlotIndex = Map.GetPlot(settlerX, settlerY):GetIndex();

    -- Don't recalculate if settler hasn't moved
    if m_LastSettlerUnitID == pUnit:GetID() and m_LastSettlerPlotIndex == settlerPlotIndex and next(m_AutoSettlerPins) ~= nil then
        return;
    end

    m_LastSettlerUnitID = pUnit:GetID();
    m_LastSettlerPlotIndex = settlerPlotIndex;

    ClearAutoSettlerPins(playerID);

    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    -- Retrieve Firaxis Strategic AI recommendations
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

    -- Scan plots within 5 hexes
    local candidates = {};
    local searchPlots = GetPlotsWithinXTiles(settlerX, settlerY, 5);

    -- Also check any AI recommendations outside 5 tiles
    for plotIdx, _ in pairs(grandAIPlots) do
        local aiPlot = Map.GetPlotByIndex(plotIdx);
        if aiPlot ~= nil then
            table.insert(searchPlots, aiPlot);
        end
    end

    local visited = {};
    for _, plot in ipairs(searchPlots) do
        local pIdx = plot:GetIndex();
        if not visited[pIdx] then
            visited[pIdx] = true;
            if IsValidCitySettlePlot(playerID, plot) then
                local score, reasons = ScoreSettlerPlot(playerID, plot, settlerX, settlerY, grandAIPlots);
                table.insert(candidates, {
                    Plot = plot,
                    Score = score,
                    Reasons = reasons
                });
            end
        end
    end

    if #candidates == 0 then
        print("DMT Smart Planner: No valid settler locations found nearby.");
        return;
    end

    -- Sort candidates descending by score
    table.sort(candidates, function(a, b) return a.Score > b.Score; end);

    -- Place Top 3 map tacks
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local topCount = math.min(3, #candidates);
    for rank = 1, topCount do
        local candidate = candidates[rank];
        local px, py = candidate.Plot:GetX(), candidate.Plot:GetY();

        -- Do not overwrite manual player pins
        local existingPin = playerCfg:GetMapPin(px, py);
        local canPlacePin = true;
        if existingPin ~= nil and not IsAutoSettlerPin(px, py) and not IsAutoDistrictPin(px, py) then
            canPlacePin = false;
        end

        if canPlacePin then
            local waterTag = candidate.Plot:IsFreshWater() and " [Fresh Water]" or (candidate.Plot:IsCoastalLand() and " [Coast]" or " [No Water]");
            local pinName = string.format("#%d Settle (Score: %d)%s", rank, candidate.Score, waterTag);

            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                pin:SetName(pinName);
                pin:SetIconName("ICON_DISTRICT_CITY_CENTER");
                pin:SetVisibility(playerID); -- Private to local player (Multiplayer safe!)

                m_AutoSettlerPins[px .. "_" .. py] = true;

                Network.BroadcastPlayerInfo();
                LuaEvents.DMT_MapPinAdded(pin);
            end
        end
    end

    print(string.format("DMT Smart Planner: Recommended %d city spots for Settler at (%d, %d)", topCount, settlerX, settlerY));
end

-- =======================================================================
-- City District Boost Optimizer
-- =======================================================================

-- Clear auto district pins for a city
function ClearAutoDistrictsForCity(playerID, cityX, cityY)
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    local cityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local hasChanges = false;
    for _, plot in ipairs(cityPlots) do
        local px, py = plot:GetX(), plot:GetY();
        local key = px .. "_" .. py;
        if m_AutoDistrictPins[key] then
            local pin = playerCfg:GetMapPin(px, py);
            if pin ~= nil then
                LuaEvents.DMT_MapPinRemoved(pin);
                playerCfg:DeleteMapPin(pin:GetID());
                hasChanges = true;
            end
            m_AutoDistrictPins[key] = nil;
        end
    end

    if hasChanges then
        Network.BroadcastPlayerInfo();
    end
end

-- Optimize all specialty districts & key infrastructure for a city
function OptimizeCityDistricts(playerID, cityX, cityY)
    if playerID ~= Game.GetLocalPlayer() then return; end
    local playerCfg = PlayerConfigurations[playerID];
    if not playerCfg then return; end

    print(string.format("DMT Smart Planner: Optimizing districts for city at (%d, %d)", cityX, cityY));

    -- 1. Remove nearby settler recommendation pins
    ClearAutoSettlerPins(playerID);

    -- 2. Gather candidate workable plots within 3 tiles
    local allCityPlots = GetPlotsWithinXTiles(cityX, cityY, 3);
    local candidatePlots = {};
    local occupiedPlots = {};

    -- Mark City Center as occupied
    occupiedPlots[Map.GetPlot(cityX, cityY):GetIndex()] = true;

    for _, plot in ipairs(allCityPlots) do
        local pIdx = plot:GetIndex();
        local px, py = plot:GetX(), plot:GetY();

        -- Check existing structures
        local hasExistingDistrict = plot:GetDistrictType() ~= -1 or plot:IsCity();
        local isForeignOwned = plot:IsOwned() and plot:GetOwner() ~= playerID;
        local isImpassable = plot:IsImpassable() or not plot:IsRevealed(playerID);

        -- Respect player manual pins
        local existingPin = playerCfg:GetMapPin(px, py);
        local hasManualPin = (existingPin ~= nil and not IsAutoDistrictPin(px, py) and not IsAutoSettlerPin(px, py));

        if hasExistingDistrict or isForeignOwned or isImpassable or hasManualPin then
            occupiedPlots[pIdx] = true;
        else
            table.insert(candidatePlots, plot);
        end
    end

    -- 3. Determine Player's Unique Districts
    local distAqueduct   = GetPlayerUniqueDistrict(playerID, "DISTRICT_AQUEDUCT");
    local distDam        = GetPlayerUniqueDistrict(playerID, "DISTRICT_DAM");
    local distIZ         = GetPlayerUniqueDistrict(playerID, "DISTRICT_INDUSTRIAL_ZONE");
    local distCommHub    = GetPlayerUniqueDistrict(playerID, "DISTRICT_COMMERCIAL_HUB");
    local distHarbor     = GetPlayerUniqueDistrict(playerID, "DISTRICT_HARBOR");
    local distCampus     = GetPlayerUniqueDistrict(playerID, "DISTRICT_CAMPUS");
    local distHolySite   = GetPlayerUniqueDistrict(playerID, "DISTRICT_HOLY_SITE");
    local distTheater    = GetPlayerUniqueDistrict(playerID, "DISTRICT_THEATER");
    local distGovPlaza   = GetPlayerUniqueDistrict(playerID, "DISTRICT_GOVERNMENT");

    local plannedDistricts = {}; -- Table of { Plot = plot, DistrictType = type, Name = name, YieldBonus = num }
    local assignedPlots = {};

    local function IsPlotAvailable(plot)
        return plot ~= nil and not occupiedPlots[plot:GetIndex()] and not assignedPlots[plot:GetIndex()];
    end

    -- -------------------------------------------------------------
    -- Step A: Aqueduct (Must be adjacent to City Center + River/Lake/Mtn)
    -- -------------------------------------------------------------
    local bestAqueduct = nil;
    if GameInfo.Districts[distAqueduct] ~= nil then
        local bestAqueductScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                if IsValidAqueductPosition(playerID, px, py) then
                    -- Score: prefer plot that has adjacent flat land for Industrial Zone!
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
                YieldBonus = 2
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step B: Dam (Floodplains with >= 2 river edges)
    -- -------------------------------------------------------------
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
                        YieldBonus = 3
                    });
                    break; -- Only 1 dam per river/city
                end
            end
        end
    end

    -- -------------------------------------------------------------
    -- Step C: Industrial Zone (Maximize Aqueduct, Dam, Strategics, Mines)
    -- -------------------------------------------------------------
    local bestIZ = nil;
    if GameInfo.Districts[distIZ] ~= nil then
        local bestIZScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distIZ, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
                    local izScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if bestAqueduct and adj:GetIndex() == bestAqueduct:GetIndex() then
                            izScore = izScore + 2; -- +2 from Aqueduct
                        end
                        if bestDam and adj:GetIndex() == bestDam:GetIndex() then
                            izScore = izScore + 2; -- +2 from Dam
                        end
                        -- Strategic resource
                        local rIdx = adj:GetResourceType();
                        if rIdx ~= -1 and GameInfo.Resources[rIdx] and GameInfo.Resources[rIdx].ResourceClassType == "RESOURCECLASS_STRATEGIC" then
                            izScore = izScore + 1;
                        end
                        -- Mines / Quarries
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
            table.insert(plannedDistricts, {
                Plot = bestIZ,
                DistrictType = distIZ,
                BaseName = Locale.Lookup(GameInfo.Districts[distIZ].Name),
                YieldBonus = math.max(1, math.floor(bestIZScore + 0.5))
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step D: Harbor (Coastal Water, adjacent to land, city center, sea resources)
    -- -------------------------------------------------------------
    local bestHarbor = nil;
    if GameInfo.Districts[distHarbor] ~= nil then
        local bestHarborScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and plot:IsWater() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distHarbor, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
                    local hScore = 0;
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY then
                            hScore = hScore + 2; -- +2 from City Center
                        end
                        if adj:GetResourceType() ~= -1 then
                            hScore = hScore + 1; -- +1 from Sea resource
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
                YieldBonus = math.max(2, bestHarborScore)
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step E: Commercial Hub (Rivers, adjacent to Harbor / other districts)
    -- -------------------------------------------------------------
    local bestCommHub = nil;
    if GameInfo.Districts[distCommHub] ~= nil then
        local bestCHScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCommHub, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
                    local chScore = 0;
                    if plot:IsRiver() then chScore = chScore + 2; end -- +2 from River
                    local adjPlots = Map.GetAdjacentPlots(px, py);
                    for _, adj in pairs(adjPlots) do
                        if bestHarbor and adj:GetIndex() == bestHarbor:GetIndex() then
                            chScore = chScore + 2; -- +2 from Harbor
                        end
                        if assignedPlots[adj:GetIndex()] or (adj:IsCity() and adj:GetX() == cityX and adj:GetY() == cityY) then
                            chScore = chScore + 0.5; -- District cluster
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
            table.insert(plannedDistricts, {
                Plot = bestCommHub,
                DistrictType = distCommHub,
                BaseName = Locale.Lookup(GameInfo.Districts[distCommHub].Name),
                YieldBonus = math.max(2, math.floor(bestCHScore + 0.5))
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step F: Campus (Mountains, Geothermal, Reefs, Rainforests)
    -- -------------------------------------------------------------
    local bestCampus = nil;
    if GameInfo.Districts[distCampus] ~= nil then
        local bestCampusScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distCampus, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
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
            table.insert(plannedDistricts, {
                Plot = bestCampus,
                DistrictType = distCampus,
                BaseName = Locale.Lookup(GameInfo.Districts[distCampus].Name),
                YieldBonus = math.max(1, math.floor(bestCampusScore + 0.5))
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step G: Holy Site (Mountains, Natural Wonders, Woods)
    -- -------------------------------------------------------------
    local bestHolySite = nil;
    if GameInfo.Districts[distHolySite] ~= nil then
        local bestHSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distHolySite, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
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
            table.insert(plannedDistricts, {
                Plot = bestHolySite,
                DistrictType = distHolySite,
                BaseName = Locale.Lookup(GameInfo.Districts[distHolySite].Name),
                YieldBonus = math.max(1, math.floor(bestHSScore + 0.5))
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step H: Theater Square (Wonders, Entertainment, High District Clusters)
    -- -------------------------------------------------------------
    local bestTheater = nil;
    if GameInfo.Districts[distTheater] ~= nil then
        local bestTSScore = -1;
        for _, plot in ipairs(candidatePlots) do
            if IsPlotAvailable(plot) and not plot:IsWater() and not plot:IsMountain() then
                local px, py = plot:GetX(), plot:GetY();
                local pinSub = { X = px, Y = py, Key = distTheater, Type = MAP_PIN_TYPES.DISTRICT };
                local canPlace = CanPlacePin(playerID, pinSub);
                if canPlace then
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
            table.insert(plannedDistricts, {
                Plot = bestTheater,
                DistrictType = distTheater,
                BaseName = Locale.Lookup(GameInfo.Districts[distTheater].Name),
                YieldBonus = math.max(1, math.floor(bestTSScore + 0.5))
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step I: Government Plaza (Central hub touching 3+ planned districts)
    -- -------------------------------------------------------------
    if GameInfo.Districts[distGovPlaza] ~= nil and not HasEmpireGovernmentPlaza(playerID) then
        local bestGov = nil;
        local bestGovScore = 2; -- Require at least 2 touching planned districts
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
                YieldBonus = bestGovScore
            });
        end
    end

    -- -------------------------------------------------------------
    -- Step J: Place Map Pins for all planned districts
    -- -------------------------------------------------------------
    local pinsToUpdate = {};
    for _, item in ipairs(plannedDistricts) do
        local px, py = item.Plot:GetX(), item.Plot:GetY();
        local pinName = string.format("%s (+%d)", item.BaseName, item.YieldBonus);
        local iconName = "ICON_" .. item.DistrictType;

        local pin = playerCfg:GetMapPin(px, py);
        if pin ~= nil then
            pin:SetName(pinName);
            pin:SetIconName(iconName);
            pin:SetVisibility(playerID); -- Private to local player (Multiplayer safe!)

            m_AutoDistrictPins[px .. "_" .. py] = true;

            local pinSubject = CreateMapPinSubject(pin);
            table.insert(pinsToUpdate, pinSubject);
        end
    end

    Network.BroadcastPlayerInfo();

    -- Notify Detailed Map Tacks to update yields for all placed pins
    for _, pinSubject in ipairs(pinsToUpdate) do
        LuaEvents.DMT_MapPinAdded(playerCfg:GetMapPin(pinSubject.X, pinSubject.Y));
    end

    if #pinsToUpdate > 0 then
        UpdatePinYields(playerID, pinsToUpdate);
    end

    UI.PlaySound("Map_Pin_Add");
    print(string.format("DMT Smart Planner: Successfully placed %d optimal district pins for city!", #plannedDistricts));
end

-- =======================================================================
-- Event Handlers
-- =======================================================================

function DMT_OnUnitSelectionChanged(playerID, unitID, hexI, hexJ, hexK, bSelected, bEditable)
    if playerID ~= Game.GetLocalPlayer() then return; end
    if not bSelected then return; end

    local pPlayer = Players[playerID];
    if not pPlayer then return; end

    local pUnit = pPlayer:GetUnits():FindID(unitID);
    if not pUnit then return; end

    local unitInfo = GameInfo.Units[pUnit:GetUnitType()];
    if unitInfo and (unitInfo.FoundCity == true or unitInfo.FoundCity == 1) then
        RecommendSettlerSpots(playerID, pUnit);
    end
end

function DMT_OnUnitMoveComplete(playerID, unitID, x, y)
    if playerID ~= Game.GetLocalPlayer() then return; end

    local pSelectedUnit = UI.GetHeadSelectedUnit();
    if pSelectedUnit ~= nil and pSelectedUnit:GetID() == unitID then
        local unitInfo = GameInfo.Units[pSelectedUnit:GetUnitType()];
        if unitInfo and (unitInfo.FoundCity == true or unitInfo.FoundCity == 1) then
            RecommendSettlerSpots(playerID, pSelectedUnit);
        end
    end
end

function DMT_OnCityAddedToMap(ownerPlayerID, cityID, cityX, cityY)
    if ownerPlayerID ~= Game.GetLocalPlayer() then return; end
    OptimizeCityDistricts(ownerPlayerID, cityX, cityY);
end

-- =======================================================================
-- Initialization
-- =======================================================================
function DMT_SmartPlanner_Initialize()
    Events.UnitSelectionChanged.Add(DMT_OnUnitSelectionChanged);
    Events.UnitMoveComplete.Add(DMT_OnUnitMoveComplete);
    Events.CityAddedToMap.Add(DMT_OnCityAddedToMap);

    -- LuaEvents for manual / console triggering
    LuaEvents.DMT_PlanDistrictsForCity.Add(OptimizeCityDistricts);
    LuaEvents.DMT_ClearAutoDistricts.Add(ClearAutoDistrictsForCity);

    print("DMT Smart Planner initialized successfully.");
end
