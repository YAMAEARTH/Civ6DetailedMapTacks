# Copacabana (`DISTRICT_WATER_STREET_CARNIVAL`)

> **คำอธิบายในเกม:**  
> A district unique to Brazil. Replaces the Water Park district, and provides +2 [ICON_Amenities] Amenities. Also unlocks the Carnival project, which grants an additional +1 [ICON_Amenities] Amenity when underway and a variety of [ICON_GreatPerson] Great People points once completed. Cannot be built in a city with a Street Carnival. Cannot be built on Reef.

---

## 1. ข้อมูลพื้นฐานและการปลดล็อก (Basic Information & Unlocking)

- **DistrictType**: `DISTRICT_WATER_STREET_CARNIVAL`
- **ชื่อภาษาอังกฤษ (Name)**: Copacabana
- **ประเภทเขต (District Category)**: Specialty District (นับโควตาประชากรเมือง Pop 1, 4, 7, 10...)
- **แทนที่เขตมาตรฐาน (Replaces)**: `DISTRICT_WATER_ENTERTAINMENT_COMPLEX` (Water Park)
- **อารยธรรม / ผู้นำเฉพาะ (Exclusive to)**: Brazil (`TRAIT_CIVILIZATION_STREET_CARNIVAL`)
- **เทคโนโลยีที่ต้องการ (PrereqTech)**: None (ไม่มี)
- **วัฒนธรรมที่ต้องการ (PrereqCivic)**: Natural History (`CIVIC_NATURAL_HISTORY`)
- **ต้นทุนการผลิตพื้นฐาน (Base Production Cost)**: 27 [ICON_Production] (สเกลตามความก้าวหน้า Tech/Civic สูงสุดถึง x10)
- **ค่าบำรุงรักษา (Maintenance)**: 1 [ICON_Gold] ทอง/เทิร์น
- **ความบันเทิง (Amenities)**: +2

---

## 2. ตารางเงื่อนไขทางเทคนิค (Technical Placement Parameters)

| พารามิเตอร์ (Parameter) | ค่าที่กำหนด (Value) | ตรรกะเชิงระบบ (Validation Logic) |
|---|---|---|
| **RequiresPlacement** | `true` | ต้องวางลงบนช่องแผนที่ (ไม่ใช่เขตในเมือง) |
| **RequiresPopulation** | `true` | ติดโควตาประชากร (Pop 1 สำหรับเขตที่ 1, Pop 4 เขตที่ 2, +3 Pop ต่อเขต) |
| **OnePerCity** | `true` | สร้างได้สูงสุด 1 แห่งต่อ 1 เมือง |
| **MaxPerPlayer** | `-1.0` | ไม่จำกัด (Unlimited) |
| **Domain / Water** | `Water / Coast` | Water / Coast (ช่องน้ำชายฝั่ง) (ต้องติดแผ่นดิน) |
| **NoAdjacentCity** | `false` | สร้างติด City Center ได้ตามปกติ |
| **Aqueduct Rule** | `false` | ไม่ใช่เขตส่งน้ำ |
| **Canal Rule** | `false` | ไม่ใช่คลอง |
| **OnePerRiver (Dam)** | `false` | ไม่ใช่เขื่อน |

---

## 3. เงื่อนไขภูมิประเทศและฟีเจอร์ (Terrain & Feature Restrictions)

- **ภูมิประเทศที่อนุญาต (Valid Terrains)**: ช่องน้ำชายฝั่ง (`TERRAIN_COAST`) ที่ติดกับแผ่นดิน
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

*ไม่มีโบนัสตำแหน่งติดกันโดยตรง (หรือมีกลไกบัฟผลผลิตเฉพาะตัว)*

---

## 5. ตรรกะการตรวจสอบสำหรับการเขียนโค้ด (Coding & Validation Checklist)

```lua
-- การตรวจสอบความถูกต้องสำหรับการวาง Copacabana (DISTRICT_WATER_STREET_CARNIVAL)
function IsValidPlotFor_DISTRICT_WATER_STREET_CARNIVAL(pPlayer, pPlot, pCity)
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
    if not pPlot:IsWater() or pPlot:GetTerrainType() ~= GameInfo.Terrains['TERRAIN_COAST'].Index then
        return false, 'MUST_BE_COAST_WATER';
    end
    if not IsAdjacentToLandPlot(playerID, px, py) then
        return false, 'MUST_BE_ADJACENT_TO_LAND';
    end

    -- 5. ตรวจสอบภูมิประเทศบังคับ (Terrain Restrictions)

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
