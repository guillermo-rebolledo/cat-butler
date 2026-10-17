# Cat calorie factors

Checked on 2026-10-17 by reading the primary sources directly: the source PDFs and pages were fetched and quoted, not summarised from memory. These numbers back the **Calorie Target**.

## Formula

RER (resting energy requirement) = 70 × (body weight in kg)^0.75.

- AAHA 2021 (Box 1), the Pet Nutrition Alliance (PNA), Merck and Ohio State all give this formula.
- Merck: the exponential form "can be used for animals of any body weight". The linear shortcut 30 × kg + 70 "is restricted to use in animals that weigh > 2 kg and < 45 kg". Kittens are often under 2 kg, so we always use the exponential form.

Calorie Target = RER × the factor below.

## Factors

| Situation | Factor | AAHA 2021 | Merck | PNA |
|---|---|---|---|---|
| Kitten (under 12 months) | **2.5** | 2.5 | 2.5 | 2–3 |
| Adult, neutered | **1.2** | 1.2–1.4 | 1.2 | 1.2 |
| Adult, intact | **1.4** | 1.4–1.6 | 1.4 | 1.4 |
| Senior (10 years and over) | **1.2** | — | — | — |

- **Senior:** the AAHA/AAFP 2021 Feline Life Stage Guidelines say that for "senior cats (greater than 10 years of age), the RER will need to be multiplied by a factor of 10–20%, and in some cases as high as 25%". That works out to 1.1–1.25, and 1.2 sits inside the range. The same guideline says seniors can lose digestive capacity, "leading to decreased BCS and thus increased caloric intake". Don't feed seniors less than adults.
- **Kittens:** a single factor (2.5) is the published value for cats. The "3 × RER under 4 months, 2 × RER after" split is the *dog* growth row in both AAHA and Merck. PNA notes that kittens' needs "start decreasing around 4 months of age". The Life Stage guideline gives 200 kcal/kg/day at 10 weeks against 80 kcal/kg/day at 10 months. One factor is coarse, which is why kittens are re-weighed every 2 weeks.
- **Neutering:** the Life Stage guideline says neutering is "a risk factor for obesity… dietary energy restriction may be appropriate". AAHA says neutering reduces energy needs, "necessitating intake reduction". Neither gives a number for kittens. The "25–30% less" figure comes from pet-food manufacturers, not guidelines. We keep 2.5 and rely on the weight trend.
- **Weight loss** (out of scope for v1): AAHA gives 0.8 and says to "base these calculations on ideal weight". PNA gives 0.8–1.0. For now this goes through the per-Cat override.

## Cross-check against WSAVA

WSAVA's chart for healthy adult cats (2020) uses NRC 2006 formulas, not RER × factor. Our neutered-adult result still falls in or near its ranges:

| Weight | Ours (RER × 1.2) | WSAVA |
|---|---|---|
| 3.0 kg | 192 kcal | 200–210 |
| 4.0 kg | 238 kcal | 225–250 |
| 4.5 kg | 259 kcal (AAHA's own worked example) | 240–270 |
| 5.0 kg | 281 kcal | 250–290 |

## Where sources disagree

The Life Stage guideline uses the linear RER × 1.0 for "young, healthy adults". For a 4 kg cat that gives 190 kcal, against 238 kcal from AAHA 2021, Merck and PNA. We follow the majority, which WSAVA's chart supports.

## Precision

Every source treats these numbers as estimates:

- Merck: "as much as 30% more or less".
- PNA and Ohio State: individual needs "can vary by as much as 50%".
- AAHA: "general guidelines… Adjustment of caloric intake should be done by monitoring BW and BCS".
- WSAVA: "for guidance only".
- Tufts: needs "can vary quite a bit".

The app must show the Calorie Target as an estimate and point to the weight trend and the vet.

## Life Stage boundaries

AAHA/AAFP 2021 define kitten as "from birth up to 1 year", young adult as 1–6 years, mature adult as 7–10 years, and senior as "aged over 10 years" ("senior cats aged 10 years and older"). The app's Life Stages are Kitten (under 1 year), Adult (1 year up to the 10th birthday) and Senior (from the 10th birthday).

## Not verified

- The NRC 2006 source text. It was only seen as cited on WSAVA's chart (lean adult: 100 × BW^0.67; obese-prone: 130 × BW^0.4).
- The PNA interactive calculator. PNA's published factor table was read directly.
- Ohio State's factor table, which is only published as an image.

## Sources

- AAHA 2021 Nutrition and Weight Management Guidelines, Box 1, p. 160: https://www.aaha.org/wp-content/uploads/globalassets/02-guidelines/2021-nutrition-and-weight-management/2021-aaha-nutrition-and-weight-management-guidelines.pdf
- 2021 AAHA/AAFP Feline Life Stage Guidelines: https://www.aaha.org/wp-content/uploads/globalassets/02-guidelines/feline-life-stage-2021/2021-aaha-aafp-feline-life-stage-guidelines.pdf
- WSAVA, Calorie Needs for Healthy Adult Cats (2020): https://wsava.org/wp-content/uploads/2020/07/Calorie-Needs-for-Healthy-Adult-Cats-updated-July-2020.pdf
- Pet Nutrition Alliance, MER/RER: https://petnutritionalliance.org/wp-content/uploads/2023/03/MER.RER_.PNA_.pdf
- Merck Veterinary Manual, maintenance energy table: https://www.merckvetmanual.com/multimedia/table/daily-maintenance-energy-requirements-for-dogs-and-cats
- Merck Veterinary Manual, nutritional requirements: https://www.merckvetmanual.com/management-and-nutrition/nutrition-small-animals/nutritional-requirements-of-small-animals
- Ohio State Companion Animal Nutrition: https://vmc.vet.osu.edu/services/companion-animal-nutrition-support-service
- Tufts Petfoodology: https://sites.tufts.edu/petfoodology/2016/02/09/how-much-should-i-feed-my-dog-or-cat/
