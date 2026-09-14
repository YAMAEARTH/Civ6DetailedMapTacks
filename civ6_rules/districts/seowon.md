# Seowon (`DISTRICT_SEOWON`)

> **คำอธิบายในเกม:**  
> A district unique to Korea for scientific endeavors. Replaces the Campus district. +4 [ICON_SCIENCE] Science. -1 [ICON_Science] Science for every adjacent district tile. Must be built on Hills.

---

## 1. ข้อมูลพื้นฐานและการปลดล็อก (Basic Information & Unlocking)

- **DistrictType**: `DISTRICT_SEOWON`
- **ชื่อภาษาอังกฤษ (Name)**: Seowon
- **ประเภทเขต (District Category)**: Specialty District (นับโควตาประชากรเมือง Pop 1, 4, 7, 10...)
- **แทนที่เขตมาตรฐาน (Replaces)**: `DISTRICT_CAMPUS` (Campus)
- **อารยธรรม / ผู้นำเฉพาะ (Exclusive to)**: Korea (`TRAIT_CIVILIZATION_DISTRICT_SEOWON`)
- **เทคโนโลยีที่ต้องการ (PrereqTech)**: Writing (`TECH_WRITING`)
- **วัฒนธรรมที่ต้องการ (PrereqCivic)**: None (ไม่มี)
- **ต้นทุนการผลิตพื้นฐาน (Base Production Cost)**: 27 [ICON_Production] (สเกลตามความก้าวหน้า Tech/Civic สูงสุดถึง x10)
- **ค่าบำรุงรักษา (Maintenance)**: 1 [ICON_Gold] ทอง/เทิร์น

---

## 2. ตารางเงื่อนไขทางเทคนิค (Technical Placement Parameters)

| พารามิเตอร์ (Parameter) | ค่าที่กำหนด (Value) | ตรรกะเชิงระบบ (Validation Logic) |
|---|---|---|
| **RequiresPlacement** | `true` | ต้องวางลงบนช่องแผนที่ (ไม่ใช่เขตในเมือง) |
| **RequiresPopulation** | `true` | ติดโควตาประชากร (Pop 1 สำหรับเขตที่ 1, Pop 4 เขตที่ 2, +3 Pop ต่อเขต) |
| **OnePerCity** | `true` | สร้างได้สูงสุด 1 แห่งต่อ 1 เมือง |
| **MaxPerPlayer** | `-1.0` | ไม่จำกัด (Unlimited) |
| **Domain / Water** | `Land` | Land Only (บนบกเท่านั้น) |
| **NoAdjacentCity** | `false` | สร้างติด City Center ได้ตามปกติ |
| **Aqueduct Rule** | `false` | ไม่ใช่เขตส่งน้ำ |
| **Canal Rule** | `false` | ไม่ใช่คลอง |
| **OnePerRiver (Dam)** | `false` | ไม่ใช่เขื่อน |

---

## 3. เงื่อนไขภูมิประเทศและฟีเจอร์ (Terrain & Feature Restrictions)

- **ภูมิประเทศที่อนุญาตเฉพาะ (Valid Terrains Only)**:
  - `TERRAIN_DESERT_HILLS` (Desert (Hills))
  - `TERRAIN_GRASS_HILLS` (Grassland (Hills))
  - `TERRAIN_PLAINS_HILLS` (Plains (Hills))
  - `TERRAIN_SNOW_HILLS` (Snow (Hills))
  - `TERRAIN_TUNDRA_HILLS` (Tundra (Hills))
  - ⚠️ **กฎบังคับ**: ต้องสร้างบน **เนินเขา (Hills Only)** เท่านั้น!
- **ฟีเจอร์ที่บังคับต้องมี (Required Features)**: ไม่มี (สร้างบนช่องโล่งได้)
- **ฟีเจอร์และภูมิประเทศต้องห้าม (Forbidden Terrains / Features)**:
  - ❌ **ภูเขา (Mountain)**: ห้ามเด็ดขาด (ยกเว้นความสามารถพิเศษบางอารยธรรม)
  - ❌ **สิ่งมหัศจรรย์ธรรมชาติ (Natural Wonders)**: ห้ามสร้างทับ
  - ❌ **น้ำแข็ง (Ice)**: ห้ามสร้างทับ
  - ℹ️ **ที่ราบน้ำท่วมถึง (Floodplains)**: ในภาค Gathering Storm สร้างทับได้ทุกเขต (ภาค Vanilla/R&F ห้ามสร้างทับยกเว้นอียิปต์)
- **ข้อจำกัดทรัพยากร (Resource Constraints)**:
  - ❌ **Luxury Resources (ทรัพยากรฟุ่มเฟือย)**: ห้ามวางทับเด็ดขาด (เอนจินเกมล็อกถาวร)
  - ❌ **Strategic Resources (ทรัพยากรยุทธศาสตร์)**: ห้ามวางทับหากเปิดเทคโนโลยีพบแร่นั้นแล้วบนแผนที่
  - ⚠️ **Bonus Resources (ทรัพยากรโบนัส)**: วางทับได้เฉพาะเมื่อผู้เล่นวิจัยเทคโนโลยีเก็บเกี่ยว (Harvest Tech) นั้นๆ แล้วเท่านั้น

---

## 4. โบนัสตำแหน่งติดกัน (Adjacency Bonuses)

| ผลผลิต (Yield) | โบนัส (Bonus) | เงื่อนไขที่อยู่ติดกัน (Adjacent Requirement) | อ็อบเจกต์เป้าหมาย (Target) | รหัสอ้างอิง (ID) |
|---|---|---|---|---|
| Science | `+4` | +{1_num} [ICON_Science] Science. | `None` | `BaseDistrict_Science` |
| Science | `+1` | เขต Government Plaza | `DISTRICT_GOVERNMENT` | `Government_Science` |
| Science | `+-1` | เขตใดๆ (Any District) | `DISTRICT_ALL` | `NegativeDistrict_Science` |

---

## 5. ตรรกะการตรวจสอบสำหรับการเขียนโค้ด (Coding & Validation Checklist)

```lua
-- การตรวจสอบความถูกต้องสำหรับการวาง Seowon (DISTRICT_SEOWON)
function IsValidPlotFor_DISTRICT_SEOWON(pPlayer, pPlot, pCity)
    if pPlot == nil then return false, 'INVALID_PLOT'; end
    local playerID = pPlayer:GetID();
    local px, py = pPlot:GetX(), pPlot:GetY();
    local distFromCity = Map.GetPlotDistance(pCity:GetX(), pCity:GetY(), px, py);

    -- 1. ตรวจสอบระยะทำงานของเมือง (Workable Range 1 - 3 ช่อง)
    if distFromCity < 1 or distFromCity > 3 then
        return false, 'OUT_OF_WORKABLE_RANGE';
    end

    -- 2. ตรวจสอบกรรมสิทธิ์ช่อง (ต้องเป็นของเมืองนี้เท่านั้น)
    if not pPlot:IsOwned() or pPlot:GetOwner() ~= playerID then
        return false, 'NOT_OWNED_BY_PLAYER';
    end
    if Cities and Cities.GetPlotPurchaseCity and Cities.GetPlotPurchaseCity(pPlot):GetID() ~= pCity:GetID() then
        return false, 'OWNED_BY_ANOTHER_CITY';
    end

    -- 3. ตรวจสอบสิ่งกีดขวางถาวร (เขตเดิม, เมือง, สิ่งมหัศจรรย์, ภูเขา)
    if pPlot:GetDistrictType() ~= -1 or pPlot:IsCity() then
        return false, 'ALREADY_OCCUPIED_BY_DISTRICT_OR_CITY';
    end
    if pPlot:IsMountain() or pPlot:IsImpassable() then
        return false, 'IMPASSABLE_OR_MOUNTAIN';
    end

    -- 4. ตรวจสอบสภาพบก/น้ำ (Water / Land Domain)
    if pPlot:IsWater() then
        return false, 'CANNOT_PLACE_ON_WATER';
    end

    -- 5. ตรวจสอบภูมิประเทศบังคับ (Terrain Restrictions)
    local validTerrains = {GameInfo.Terrains['TERRAIN_DESERT_HILLS'].Index, GameInfo.Terrains['TERRAIN_GRASS_HILLS'].Index, GameInfo.Terrains['TERRAIN_PLAINS_HILLS'].Index, GameInfo.Terrains['TERRAIN_SNOW_HILLS'].Index, GameInfo.Terrains['TERRAIN_TUNDRA_HILLS'].Index};
    local tIdx = pPlot:GetTerrainType();
    local isValidTerrain = false;
    for _, val in ipairs(validTerrains) do if tIdx == val then isValidTerrain = true; break; end end
    if not isValidTerrain then return false, 'INVALID_TERRAIN'; end

    -- 6. ตรวจสอบฟีเจอร์บังคับ (Required Features)

    -- 7. ตรวจสอบกฎการประชิดเมือง (City Center Adjacency)

    -- 8. ตรวจสอบทรัพยากร (Resource Check)
    local resIdx = pPlot:GetResourceType();
    if resIdx ~= -1 then
        local resInfo = GameInfo.Resources[resIdx];
        if resInfo.ResourceClassType == 'RESOURCECLASS_LUXURY' then return false, 'CANNOT_CRUSH_LUXURY'; end
        if resInfo.ResourceClassType == 'RESOURCECLASS_STRATEGIC' and pPlayer:GetResources():IsResourceVisible(resInfo.Hash) then
            return false, 'CANNOT_CRUSH_REVEALED_STRATEGIC';
        end
        if not CanHarvestResource(resInfo.ResourceType) then return false, 'CANNOT_HARVEST_BONUS_RES'; end
    end

    return true, 'VALID_PLACEMENT';
end
```
