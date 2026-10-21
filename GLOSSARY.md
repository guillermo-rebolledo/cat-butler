# Cat Butler

A daily companion for cat owners, especially first-time ones: it plans and records feeding, keeps track of recurring care, and watches each cat's weight.

## Language

### People and cats

**Cat**:
One animal cared for in the app; every plan, record and reminder belongs to exactly one Cat.
_Avoid_: Pet, animal, kitty

**Archived Cat**:
A Cat no longer in the Household's care (rehomed or passed away); its history is kept and its reminders stop.
_Avoid_: Deleted cat, inactive cat

**Household**:
The group of people who share care of the same Cats; it owns its Cats and everything recorded about them.
_Avoid_: Family, team, account

### Feeding

**Meal**:
A planned feeding on the schedule (e.g. "breakfast, 08:00").
_Avoid_: Feeding time, slot

**Feeding**:
A record that food was actually given to a Cat.
_Avoid_: Meal log, entry

**Off-schedule Feeding**:
A Feeding that fulfilled no Meal: one not within 2 hours of a Meal still unfulfilled, or one of a free-fed Food.
_Avoid_: Extra feeding, snack

**Missed Meal**:
A Meal whose window passed without a Feeding fulfilling it. A Meal added or moved after its window passed isn't Missed until the next day, unless it was already Missed.
_Avoid_: Skipped meal, late meal

**Meal Reminder**:
A notification about a Meal, with a Fed ✓ action that logs the Meal's usual Feeding: one at the Meal's time, and one follow-up 30 minutes later unless the Meal was fulfilled by then.
_Avoid_: Alert, alarm

**Food**:
A specific product or food a Cat eats, with its serving unit (can, pouch, gram, cup) and calories per unit; a Food may be marked as a treat or as free-fed.
_Avoid_: Product, brand, item

**Retired Food**:
A Food the Household no longer buys; it leaves the pickers but keeps its details for past Feedings.
_Avoid_: Deleted food, archived food

**Intake**:
The calories a Cat ate in a day, summed from its Feedings and how much of each it ate; approximate when any was of a free-fed Food.
_Avoid_: Consumption, total

**Calorie Target**:
The daily calories a Cat should eat, estimated from its latest Weigh-in, Life Stage and neuter status, unless the owner sets their own (e.g. the vet's number).
_Avoid_: Recommendation, portion advice

### Health

**Life Stage**:
A Cat's age band (Kitten under 12 months, Adult, Senior from 10 years), derived from its birthdate.
_Avoid_: Age group, category

**Care Task**:
A one-off or recurring health obligation for a Cat with a due date, such as a vaccine, deworming, flea treatment or vet checkup. Due soon within a week of its due date, overdue from the day after; a recurring one is next due one interval after its latest Care Record (or, once its only Care Record is deleted, from that record's date), and a one-off one is done once it has a Care Record.
_Avoid_: Reminder, appointment

**Care Record**:
The dated record of a Care Task being done, with any notes from the vet.
_Avoid_: Vet visit, history entry, completion

**Care Reminder**:
A notification about a Care Task in time to book the vet: by default one 3 days before its due date and one on the day, both at 09:00; Settings changes the days and the time. An overdue Care Task gets none, only its badge.
_Avoid_: Alert, vet reminder

**Weigh-in**:
One recorded measurement of a Cat's weight on a date.
_Avoid_: Weight entry, measurement

**Health Note**:
A dated observation about a Cat's health or behaviour, kept so it can be shown to a vet.
_Avoid_: Symptom, journal entry, log
