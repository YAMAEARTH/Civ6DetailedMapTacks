# ดัชนีกฎและเงื่อนไขการสร้างเขตทั้งหมดใน Civilization VI (Gathering Storm)

เอกสารสรุปกฎ เงื่อนไขทางเทคนิค ภูมิประเทศต้องห้าม และตรรกะการตรวจสอบสำหรับการเขียนโค้ด (Placement Validation Logic) สกัดตรงจากฐานข้อมูลเกม `DebugGameplay.sqlite`

---

## รายชื่อเขตทั้งหมด (All Districts Table)

| เขต (District) | DistrictType | ประเภท (Category) | แทนที่ (Replaces) | ปลดล็อก (Unlock) | โดเมน (Domain) | ไฟล์เอกสาร (File) |
|---|---|---|---|---|---|---|
| **Acropolis** | `DISTRICT_ACROPOLIS` | Specialty | `Theater Square` | Drama and Poetry | Land | [acropolis.md](./acropolis.md) |
| **Aerodrome** | `DISTRICT_AERODROME` | Specialty | `None (Standard District)` | Flight | Land | [aerodrome.md](./aerodrome.md) |
| **Campus** | `DISTRICT_CAMPUS` | Specialty | `None (Standard District)` | Writing | Land | [campus.md](./campus.md) |
| **Commercial Hub** | `DISTRICT_COMMERCIAL_HUB` | Specialty | `None (Standard District)` | Currency | Land | [commercial_hub.md](./commercial_hub.md) |
| **Copacabana** | `DISTRICT_WATER_STREET_CARNIVAL` | Specialty | `Water Park` | Natural History | Water | [water_street_carnival.md](./water_street_carnival.md) |
| **Cothon** | `DISTRICT_COTHON` | Specialty | `Harbor` | Celestial Navigation | Water | [cothon.md](./cothon.md) |
| **Diplomatic Quarter** | `DISTRICT_DIPLOMATIC_QUARTER` | Specialty | `None (Standard District)` | Mathematics | Land | [diplomatic_quarter.md](./diplomatic_quarter.md) |
| **Encampment** | `DISTRICT_ENCAMPMENT` | Specialty | `None (Standard District)` | Bronze Working | Land | [encampment.md](./encampment.md) |
| **Entertainment Complex** | `DISTRICT_ENTERTAINMENT_COMPLEX` | Specialty | `None (Standard District)` | Games and Recreation | Land | [entertainment_complex.md](./entertainment_complex.md) |
| **Floating Market** | `DISTRICT_SUK_FLOATINGMARKET` | Specialty | `Commercial Hub` | Currency | Land | [suk_floatingmarket.md](./suk_floatingmarket.md) |
| **Government Plaza** | `DISTRICT_GOVERNMENT` | Specialty | `None (Standard District)` | State Workforce | Land | [government_plaza.md](./government_plaza.md) |
| **Hansa** | `DISTRICT_HANSA` | Specialty | `Industrial Zone` | Apprenticeship | Land | [hansa.md](./hansa.md) |
| **Harbor** | `DISTRICT_HARBOR` | Specialty | `None (Standard District)` | Celestial Navigation | Water | [harbor.md](./harbor.md) |
| **Hippodrome** | `DISTRICT_HIPPODROME` | Specialty | `Entertainment Complex` | Games and Recreation | Land | [hippodrome.md](./hippodrome.md) |
| **Holy Site** | `DISTRICT_HOLY_SITE` | Specialty | `None (Standard District)` | Astrology | Land | [holy_site.md](./holy_site.md) |
| **Ikanda** | `DISTRICT_IKANDA` | Specialty | `Encampment` | Bronze Working | Land | [ikanda.md](./ikanda.md) |
| **Industrial Zone** | `DISTRICT_INDUSTRIAL_ZONE` | Specialty | `None (Standard District)` | Apprenticeship | Land | [industrial_zone.md](./industrial_zone.md) |
| **Lavra** | `DISTRICT_LAVRA` | Specialty | `Holy Site` | Astrology | Land | [lavra.md](./lavra.md) |
| **Observatory** | `DISTRICT_OBSERVATORY` | Specialty | `Campus` | Writing | Land | [observatory.md](./observatory.md) |
| **Oppidum** | `DISTRICT_OPPIDUM` | Specialty | `Industrial Zone` | Iron Working | Land | [oppidum.md](./oppidum.md) |
| **Preserve** | `DISTRICT_PRESERVE` | Specialty | `None (Standard District)` | Mysticism | Land | [preserve.md](./preserve.md) |
| **Royal Navy Dockyard** | `DISTRICT_ROYAL_NAVY_DOCKYARD` | Specialty | `Harbor` | Celestial Navigation | Water | [royal_navy_dockyard.md](./royal_navy_dockyard.md) |
| **Seowon** | `DISTRICT_SEOWON` | Specialty | `Campus` | Writing | Land | [seowon.md](./seowon.md) |
| **Street Carnival** | `DISTRICT_STREET_CARNIVAL` | Specialty | `Entertainment Complex` | Games and Recreation | Land | [street_carnival.md](./street_carnival.md) |
| **Suguba** | `DISTRICT_SUGUBA` | Specialty | `Commercial Hub` | Currency | Land | [suguba.md](./suguba.md) |
| **Theater Square** | `DISTRICT_THEATER` | Specialty | `None (Standard District)` | Drama and Poetry | Land | [theater_square.md](./theater_square.md) |
| **Water Park** | `DISTRICT_WATER_ENTERTAINMENT_COMPLEX` | Specialty | `None (Standard District)` | Natural History | Water | [water_entertainment_complex.md](./water_entertainment_complex.md) |
| **Aqueduct** | `DISTRICT_AQUEDUCT` | Non-Specialty | `None (Standard District)` | Engineering | Land | [aqueduct.md](./aqueduct.md) |
| **Bath** | `DISTRICT_BATH` | Non-Specialty | `Aqueduct` | Engineering | Land | [bath.md](./bath.md) |
| **Canal** | `DISTRICT_CANAL` | Non-Specialty | `None (Standard District)` | Steam Power | Land | [canal.md](./canal.md) |
| **City Center** | `DISTRICT_CITY_CENTER` | Non-Specialty | `None (Standard District)` | None | Land | [city_center.md](./city_center.md) |
| **Dam** | `DISTRICT_DAM` | Non-Specialty | `None (Standard District)` | Buttress | Land | [dam.md](./dam.md) |
| **Foko** | `DISTRICT_HAG_MADAGASCAR_FOKO` | Non-Specialty | `Neighborhood` | Craftsmanship | Land | [hag_madagascar_foko.md](./hag_madagascar_foko.md) |
| **Mbanza** | `DISTRICT_MBANZA` | Non-Specialty | `Neighborhood` | Guilds | Land | [mbanza.md](./mbanza.md) |
| **Neighborhood** | `DISTRICT_NEIGHBORHOOD` | Non-Specialty | `None (Standard District)` | Urbanization | Land | [neighborhood.md](./neighborhood.md) |
| **Spaceport** | `DISTRICT_SPACEPORT` | Non-Specialty | `None (Standard District)` | Rocketry | Land | [spaceport.md](./spaceport.md) |
| **Thành** | `DISTRICT_THANH` | Non-Specialty | `Encampment` | Bronze Working | Land | [thanh.md](./thanh.md) |
| **Wonder** | `DISTRICT_WONDER` | Non-Specialty | `None (Standard District)` | None | Land | [wonder.md](./wonder.md) |

---

## หมวดหมู่หลัก (Major Classifications)

1. **Specialty Districts (เขตพิเศษติดโควตาประชากร)**:

   - ต้องใช้ประชากรเมืองในการปลดล็อกสร้าง: ช่องที่ 1 (Pop 1), ช่องที่ 2 (Pop 4), ช่องที่ 3 (Pop 7), +3 Pop ต่อเขต (เยอรมนีสร้างได้ +1 เขตพิเศษฟรี)

   - ตัวอย่าง: Campus, Holy Site, Commercial Hub, Industrial Zone, Harbor, Encampment, Theater Square, Entertainment Complex, Aerodrome, Preserve


2. **Non-Specialty Districts (เขตโครงสร้างพื้นฐาน/ไม่จำกัด Pop)**:

   - สร้างได้อิสระทันทีที่วิจัยเทคโนโลยี/วัฒนธรรมถึง ไม่ต้องรอประชากรเมืองเติบโต

   - ตัวอย่าง: Aqueduct, Dam, Canal, Neighborhood, Spaceport, Government Plaza, Diplomatic Quarter


3. **National Unique Districts (เขตจำกัด 1 แห่งต่อทั้งอาณาจักร)**:

   - `DISTRICT_GOVERNMENT` (Government Plaza - รัฐสภา)

   - `DISTRICT_DIPLOMATIC_QUARTER` (Diplomatic Quarter - เขตการทูต)


4. **Engineering Districts (เขตวิศวกรรมที่เร่งสร้างได้ด้วย Military Engineer)**:

   - ในภาค Gathering Storm: Aqueduct, Dam, Canal สามารถใช้ทหารช่าง (Military Engineer) 1 ชาร์จ เร่งการผลิตได้ 20% ทันที
