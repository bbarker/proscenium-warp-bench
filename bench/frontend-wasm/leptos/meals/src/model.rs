//! The meals benchmark's data, shared word for word with its Unison twin
//! (`bench.meals` in `unison/scratch/proscenium--perf-r5m.u`): a seeded catalog
//! of 240 recipes, a week of 7 days with 4 meals each drawn from it, the
//! grocery list the week needs, and the edits the page makes. Every number
//! comes from the same linear congruential generator as the rows benchmark,
//! so both implementations draw the same week.

use std::collections::BTreeMap;

pub static METHODS: &[&str] = &[
    "roasted", "grilled", "baked", "steamed", "seared", "braised", "spiced", "smoky", "herby",
    "lemony", "crispy", "slow-cooked",
];
pub static PROTEINS: &[&str] = &[
    "chicken", "salmon", "tofu", "turkey", "lentil", "egg", "beef", "shrimp", "chickpea", "pork",
];
pub static FORMS: &[&str] = &[
    "bowl", "salad", "wrap", "stew", "skillet", "tacos", "soup", "traybake",
];
pub static INGREDIENTS: &[&str] = &[
    "spinach", "chicken thighs", "milk", "sourdough", "brown rice", "frozen peas", "cumin",
    "sparkling water", "tomatoes", "salmon fillets", "greek yogurt", "tortillas", "lentils",
    "frozen berries", "paprika", "orange juice", "onions", "ground turkey", "cheddar", "pita",
    "chickpeas", "frozen corn", "oregano", "green tea", "peppers", "tofu", "eggs", "bagels",
    "quinoa", "frozen spinach", "chili flakes", "oat milk", "carrots", "shrimp", "butter",
    "rye bread", "pasta", "edamame", "turmeric", "kombucha", "lemons", "pork loin", "feta",
    "naan", "oats", "frozen mango", "black pepper", "coconut water",
];
pub static AISLES: &[&str] = &[
    "Produce", "Meat and fish", "Dairy and eggs", "Bakery", "Pantry", "Frozen", "Spices",
    "Drinks",
];
pub static DAYS: &[&str] = &[
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
];
pub static KINDS: &[&str] = &["Breakfast", "Lunch", "Dinner", "Snack"];

pub const CATALOG_SIZE: usize = 240;
const PER_KIND: u64 = 60;

/// The generator both implementations share.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Seed(pub u64);

impl Seed {
    pub fn draw(&mut self, bound: u64) -> u64 {
        self.0 = (self.0 * 1_103_515_245 + 12_345) % 2_147_483_648;
        (self.0 / 65_536) % bound
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Recipe {
    pub name: String,
    pub kcal: u64,
    pub protein: u64,
    pub carbs: u64,
    pub fat: u64,
    pub ingredients: [usize; 3],
}

/// 240 recipes; recipe `i` is a `KINDS[i % 4]`.
pub fn catalog() -> Vec<Recipe> {
    let mut seed = Seed(7);
    (0..CATALOG_SIZE)
        .map(|_| {
            let name = [
                METHODS[seed.draw(12) as usize],
                PROTEINS[seed.draw(10) as usize],
                FORMS[seed.draw(8) as usize],
            ]
            .join(" ");
            let kcal = 150 + seed.draw(550);
            let protein = 5 + seed.draw(45);
            let carbs = 10 + seed.draw(80);
            let fat = 3 + seed.draw(40);
            let ingredients = [seed.draw(48) as usize, seed.draw(48) as usize, seed.draw(48) as usize];
            Recipe { name, kcal, protein, carbs, fat, ingredients }
        })
        .collect()
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Slot {
    pub id: usize,
    pub kind: usize,
    pub recipe: usize,
    pub servings: u64,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Day {
    pub id: usize,
    pub slots: Vec<Slot>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Plan {
    pub days: Vec<Day>,
    pub seed: Seed,
}

impl Plan {
    /// A fresh week, Monday first, one serving of each meal.
    pub fn draw(mut seed: Seed) -> Plan {
        let days = (0..7)
            .map(|day| Day {
                id: day,
                slots: (0..4)
                    .map(|kind| Slot {
                        id: day * 10 + kind,
                        kind,
                        recipe: seed.draw(PER_KIND) as usize * 4 + kind,
                        servings: 1,
                    })
                    .collect(),
            })
            .collect();
        Plan { days, seed }
    }

    pub fn replan(&self) -> Plan {
        Plan::draw(self.seed)
    }

    fn edit_slot(&self, slot_id: usize, edit: impl Fn(Slot, &mut Seed) -> Option<Slot>) -> Plan {
        let mut seed = self.seed;
        let days = self
            .days
            .iter()
            .map(|day| Day {
                id: day.id,
                slots: day
                    .slots
                    .iter()
                    .filter_map(|slot| if slot.id == slot_id { edit(*slot, &mut seed) } else { Some(*slot) })
                    .collect(),
            })
            .collect();
        Plan { days, seed }
    }

    /// Another recipe of the same kind, never the one it had.
    pub fn shuffle(&self, slot_id: usize) -> Plan {
        self.edit_slot(slot_id, |slot, seed| {
            let drawn = seed.draw(PER_KIND) as usize * 4 + slot.kind;
            let recipe = if drawn == slot.recipe { (drawn / 4 + 1) % PER_KIND as usize * 4 + slot.kind } else { drawn };
            Some(Slot { recipe, ..slot })
        })
    }

    pub fn add_serving(&self, slot_id: usize) -> Plan {
        self.edit_slot(slot_id, |slot, _| Some(Slot { servings: slot.servings + 1, ..slot }))
    }

    pub fn remove(&self, slot_id: usize) -> Plan {
        self.edit_slot(slot_id, |_, _| None)
    }

    /// The first day moves to the end of the week.
    pub fn rotate(&self) -> Plan {
        let mut days = self.days.clone();
        days.rotate_left(1);
        Plan { days, seed: self.seed }
    }
}

#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub struct Totals {
    pub kcal: u64,
    pub protein: u64,
    pub carbs: u64,
    pub fat: u64,
}

pub fn day_totals(recipes: &[Recipe], day: &Day) -> Totals {
    day.slots.iter().fold(Totals::default(), |sum, slot| {
        let recipe = &recipes[slot.recipe];
        Totals {
            kcal: sum.kcal + recipe.kcal * slot.servings,
            protein: sum.protein + recipe.protein * slot.servings,
            carbs: sum.carbs + recipe.carbs * slot.servings,
            fat: sum.fat + recipe.fat * slot.servings,
        }
    })
}

pub fn totals_text(totals: Totals) -> String {
    format!(
        "{} kcal · {} g protein · {} g carbs · {} g fat",
        totals.kcal, totals.protein, totals.carbs, totals.fat
    )
}

pub fn week_text(recipes: &[Recipe], plan: &Plan) -> String {
    let week = plan.days.iter().fold(Totals::default(), |sum, day| {
        let day = day_totals(recipes, day);
        Totals {
            kcal: sum.kcal + day.kcal,
            protein: sum.protein + day.protein,
            carbs: sum.carbs + day.carbs,
            fat: sum.fat + day.fat,
        }
    });
    format!("Week: {}", totals_text(week))
}

/// The bar widths of a day's macros panel: kcal, protein, carbs and fat
/// against 2,000, 120, 250 and 70, capped at 100.
pub fn bar_widths(totals: Totals) -> [u64; 4] {
    [(totals.kcal, 2_000), (totals.protein, 120), (totals.carbs, 250), (totals.fat, 70)]
        .map(|(value, target)| (value * 100 / target).min(100))
}

/// Servings of each ingredient the week needs, by ingredient index.
pub fn grocery_counts(recipes: &[Recipe], plan: &Plan) -> BTreeMap<usize, u64> {
    plan.days
        .iter()
        .flat_map(|day| day.slots.iter())
        .flat_map(|slot| recipes[slot.recipe].ingredients.map(|ingredient| (ingredient, slot.servings)))
        .fold(BTreeMap::new(), |mut counts, (ingredient, servings)| {
            *counts.entry(ingredient).or_insert(0) += servings;
            counts
        })
}

/// The unchecked items by aisle (aisle order, then name), and the checked
/// ones by name.
pub fn grocery_sections(
    counts: &BTreeMap<usize, u64>,
    checked: &[String],
) -> (Vec<(&'static str, Vec<(&'static str, u64)>)>, Vec<(&'static str, u64)>) {
    let by_name = |mut items: Vec<(&'static str, u64)>| {
        items.sort_by(|left, right| left.0.cmp(right.0));
        items
    };
    let is_checked = |ingredient: usize| checked.iter().any(|name| name == INGREDIENTS[ingredient]);
    let aisles = AISLES
        .iter()
        .enumerate()
        .map(|(aisle, name)| {
            let items = counts
                .iter()
                .filter(|(ingredient, _)| **ingredient % 8 == aisle && !is_checked(**ingredient))
                .map(|(ingredient, count)| (INGREDIENTS[*ingredient], *count))
                .collect();
            (*name, by_name(items))
        })
        .filter(|(_, items)| !items.is_empty())
        .collect();
    let done = counts
        .iter()
        .filter(|(ingredient, _)| is_checked(**ingredient))
        .map(|(ingredient, count)| (INGREDIENTS[*ingredient], *count))
        .collect();
    (aisles, by_name(done))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_week_is_the_one_the_unison_twin_draws() {
        let recipes = catalog();
        let plan = Plan::draw(Seed(42));
        assert_eq!(recipes[0].name, catalog()[0].name);
        assert_eq!(plan.days.len(), 7);
        assert!(plan.days.iter().all(|day| day.slots.len() == 4));
        println!("{} | {}", recipes[0].name, week_text(&recipes, &plan));
    }
}
