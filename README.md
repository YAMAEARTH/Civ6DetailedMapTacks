# Civ6 Detailed Map Tacks - Smart Planner Edition

Enhanced edition of **Detailed Map Tacks** for *Sid Meier's Civilization VI* featuring automated Settler spot recommendation and multi-district adjacency boost optimization across all 16 districts.

100% Client-Side UI Mod — **Safe for Single-Player and Multiplayer without requiring other players or the host to install the mod**.

---

## 🌟 Key Features

### 1. Automatic Settler City Recommendations
* **Top 3 Settler Spots**: Whenever a Settler is selected or moved, the surrounding map is analyzed and the top 3 city plots are marked with Map Tacks (`#1`, `#2`, `#3`) and scores.
* **Golden Distance (4–5 Tiles)**: Optimal distance scoring balances 6-tile AoE synergy (Factory, Power Plant, Colosseum) and shared district triangles (e.g. Aqueduct + Industrial Zone) with minimal workable tile overlap.
* **Fresh Water & Housing Priority**: Prioritizes fresh water (River/Lake/Oasis) with heavy scoring (+32 pts vs -25 penalty for dry land).
* **Gathering Storm Loyalty Protection**: Scans per-tile foreign loyalty pressure. Sites with critical loyalty risk ($\le -10$) are strictly disqualified from recommendations to prevent cities from flipping into Free Cities.
* **Claiming Vital Resources**: Distant settling ($\ge 7$ tiles) is penalized unless the site claims a new unowned Strategic or Luxury resource in safe loyalty territory.

### 2. Automated District Boost Optimizer (All 16 Districts)
* **Automatic Planning on City Foundation**: Placing a city or pressing `Shift + A` automatically generates an optimal constraint-satisfied layout for all 16 specialty districts.
* **Dam 1-per-River & River Floodplain Rule**: Strictly validates that no other city has a Dam on the same river system, and restricts Dams to true river floodplains (coastal lowlands strictly forbidden).
* **Resource Preservation & Harvest Requirements**:
  * Luxury resources are never crushed.
  * Researched Strategic resources are never crushed.
  * Bonus resources (Stone, Wheat, Cattle, Deer, etc.) can only be planned if the required Harvest technology has already been researched by the player.
* **Canal Geometry (60° Turn Rule)**: Flat land connecting 2 water bodies or 1 water body + City Center with endpoints at least 2 tiles apart to prevent illegal sharp bends.
* **Civilization-Specific Unique Districts**:
  * *Korea (Seowon)*: Must be on Hills, isolated from all other districts to avoid the -1 penalty.
  * *Kongo (Mbanza)*: Placed on Woods/Rainforest regardless of Appeal.
  * *Vietnam (Thành & specialty districts)*: Restricted to Woods/Rainforest/Marsh.
  * *Gaul (Oppidum)*: Placed at least 2 tiles away from City Center.
* **Population Slot Ranking**: Non-specialty districts (Aqueduct, Dam, Canal, Neighborhood, Spaceport, Gov Plaza, Diplo Quarter) are marked as free ("ไม่จำกัด Pop"), while specialty districts are prioritized according to Pop threshold requirements (Pop 1, 4, 7...).
* **Turn-by-Turn Dynamic Validation**: Scans every turn. If foreign borders expand over a planned tile or a district is built, the tack is cleaned up and remaining districts are dynamically re-routed.

---

## 🎮 Controls & Shortcuts

| Action | Control |
| :--- | :--- |
| **Smart Planner Hotkey** | **`Shift + A`** |
| **Close Active Panels** | **`ESC`** or click **`[X]`** button |
| **Delete Single Map Tack** | **`Shift + Right Click`** on map tack flag |
| **Toggle Tack Visibility** | Click Map Pin List button on minimap panel |

### Hotkey Behavior (`Shift + A`):
1. **Settler Selected**: Recommends Top 3 settling locations and displays HUD recommendation panel.
2. **City Selected**: Optimizes and pins districts for the selected city.
3. **Mouse Over City Tile**: Optimizes districts for the owning city under the cursor.
4. **Any Settler Available**: Selects Settler, centers camera, and displays recommendations.
5. **Fallback**: Focuses Capital and optimizes district layouts.

---

## 🛡️ Stability & Compatibility

* **Compatibility**: Base Game, Rise & Fall, Gathering Storm, New Frontier Pass.
* **Multiplayer Safe**: Runs purely in the `<AddUserInterfaces Context="InGame">` UI layer with `<AffectsSavedGames>0</AffectsSavedGames>`. Generated map tacks are marked private (`pin:SetVisibility(localPlayerID)`) preventing any desynchronization.
* **Engine Memory Protection**: Fully protected against C++ vector mutation crashes (`EXCEPTION_ACCESS_VIOLATION 0xffffffff`), with safe post-loop pin deletion and turn-level event debouncing.

---

## 📂 Documentation

For comprehensive formulas, architectural diagrams, scoring tables, and memory safety rules, refer to [.mdagent.md](.mdagent.md).
