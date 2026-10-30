//! A meal-planning page, written the way a real Leptos meal planner writes
//! its Meals page: the week is one signal, and any edit to it re-renders the
//! whole week, its totals and the grocery list from a closure (no keyed
//! `<For>`); a day card's open panels are signals local to the card; the
//! recipe search re-renders its result list on every keystroke from an input
//! that never reads its own value; moving a day animates the cards that moved
//! with a FLIP spring written straight to their `style.transform`, one rAF
//! frame at a time; and the mascot is inline SVG animated by CSS alone.
//! Its Unison twin is `bench.meals.ui`; the data is in `model.rs`.

mod model;

use leptos::prelude::*;
use model::{Plan, Recipe, Seed, DAYS, KINDS};
use std::rc::Rc;
use wasm_bindgen::{prelude::wasm_bindgen, JsCast};

/// The mascot's markup, set as inner HTML as a real app sets a generated
/// sprite; the page's stylesheet animates `.mascot-whole` and `.mascot-limb`.
const MASCOT_SVG: &str = r##"<svg viewBox="0 0 120 120" width="120" height="120"><g class="mascot-whole"><ellipse cx="60" cy="74" rx="30" ry="36" fill="#7bc"/><circle cx="60" cy="34" r="22" fill="#9cd"/><circle cx="52" cy="30" r="3"/><circle cx="68" cy="30" r="3"/><g class="mascot-limb"><rect x="84" y="56" width="10" height="34" rx="5" fill="#7bc"/></g></g></svg>"##;

const FLIP_FRAMES: u32 = 30;

#[component]
fn ActionButton(id: &'static str, text: &'static str) -> impl IntoView {
    view! { <button id=id>{text}</button> }
}

/// One meal: its picture, name and numbers, and a "more" tray of controls.
fn view_slot(recipes: &'static [Recipe], slot: model::Slot, plan: RwSignal<Option<Plan>>, tray_open: RwSignal<Option<usize>>) -> impl IntoView {
    let recipe = &recipes[slot.recipe];
    let slot_id = slot.id;
    let edit = move |change: fn(&Plan, usize) -> Plan| {
        move |_| plan.update(|plan| *plan = plan.as_ref().map(|plan| change(plan, slot_id)))
    };
    view! {
        <div class="slot" data-slot=slot_id.to_string()>
            <span class="thumb"></span>
            <div class="slot-main">
                <span class="slot-type">{KINDS[slot.kind]}</span>
                <span class="slot-name">{recipe.name.clone()}</span>
                <span class="slot-kcal">{format!("{} kcal", recipe.kcal * slot.servings)}</span>
                <span class="slot-protein">{format!("{} g protein", recipe.protein * slot.servings)}</span>
            </div>
            <button class="more" on:click=move |_| tray_open.update(|open| *open = if *open == Some(slot_id) { None } else { Some(slot_id) })>"⋯"</button>
            <div class=move || if tray_open.get() == Some(slot_id) { "tray" } else { "tray hidden" }>
                <button class="info">"Info"</button>
                <button class="recipe">"Recipe"</button>
                <span class="servings">{slot.servings.to_string()}</span>
                <button class="serv-plus" on:click=edit(Plan::add_serving)>"+"</button>
                <button class="shuffle" on:click=edit(Plan::shuffle)>"Shuffle"</button>
                <button class="remove" on:click=edit(Plan::remove)>"Remove"</button>
            </div>
        </div>
    }
}

/// One day: its totals, a macros panel it can open, and its meals.
fn view_day(recipes: &'static [Recipe], day: &model::Day, plan: RwSignal<Option<Plan>>) -> impl IntoView {
    let macros_open = RwSignal::new(false);
    let tray_open = RwSignal::new(None::<usize>);
    let totals = model::day_totals(recipes, day);
    let widths = model::bar_widths(totals);
    let slots = day.slots.iter().map(|slot| view_slot(recipes, *slot, plan, tray_open)).collect_view();
    view! {
        <section class="day" id=format!("day-{}", day.id) data-flip-key=format!("day-{}", day.id)>
            <h3 class="day-name">{DAYS[day.id]}</h3>
            <p class="day-totals">{model::totals_text(totals)}</p>
            <button class="macros-toggle" on:click=move |_| macros_open.update(|open| *open = !*open)>"Calories and macros"</button>
            {move || macros_open.get().then(|| view! {
                <div class="macros">
                    {widths.map(|width| view! { <div class="bar" style=format!("width: {width}%")></div> }).to_vec()}
                </div>
            })}
            {slots}
        </section>
    }
}

/// The grocery list the week needs, by aisle, with checked items kept at the
/// foot; re-rendered whole when the week or a check changes.
fn view_grocery(recipes: &'static [Recipe], plan: &Plan, checked: RwSignal<Vec<String>>) -> impl IntoView {
    let counts = model::grocery_counts(recipes, plan);
    let toggle = move |name: &'static str| {
        move |_| checked.update(|checked| match checked.iter().position(|item| item == name) {
            Some(index) => {
                checked.remove(index);
            }
            None => checked.push(name.to_string()),
        })
    };
    let item = move |(name, count): (&'static str, u64)| view! {
        <li class="item" data-name=name>
            <button class="check" on:click=toggle(name)>"✓"</button>
            <span class="name">{name}</span>
            <span class="qty">{format!("×{count}")}</span>
        </li>
    };
    move || {
        let (aisles, done) = checked.with(|checked| model::grocery_sections(&counts, checked));
        view! {
            {aisles.into_iter().map(|(aisle, items)| view! {
                <section class="aisle">
                    <h4>{aisle}</h4>
                    <ul>{items.into_iter().map(item).collect_view()}</ul>
                </section>
            }).collect_view()}
            <section id="checked">
                <h4>"Checked"</h4>
                <ul>{done.into_iter().map(item).collect_view()}</ul>
            </section>
        }
    }
}

/// Where each `[data-flip-key]` element is now.
fn flip_positions() -> Vec<(String, web_sys::HtmlElement, f64, f64)> {
    let nodes = document().query_selector_all("[data-flip-key]").unwrap();
    (0..nodes.length())
        .filter_map(|index| nodes.item(index))
        .filter_map(|node| node.dyn_into::<web_sys::HtmlElement>().ok())
        .map(|element| {
            let rect = element.get_bounding_client_rect();
            (element.get_attribute("data-flip-key").unwrap_or_default(), element, rect.left(), rect.top())
        })
        .collect()
}

/// One frame of the spring: each moved element `remaining` of the way back
/// from where it was; the last frame clears the transforms and reports how
/// many elements moved on `body[data-flip]`.
fn flip_frame(moved: Rc<Vec<(web_sys::HtmlElement, f64, f64)>>, frame: u32) {
    if frame < FLIP_FRAMES {
        let remaining = (f64::from(FLIP_FRAMES - frame) / f64::from(FLIP_FRAMES)).powi(3);
        moved.iter().for_each(|(element, dx, dy)| {
            _ = element.style().set_property("transform", &format!("translate({}px, {}px)", dx * remaining, dy * remaining));
        });
        request_animation_frame(move || flip_frame(moved, frame + 1));
    } else {
        moved.iter().for_each(|(element, _, _)| {
            _ = element.style().remove_property("transform");
        });
        _ = document().body().unwrap().set_attribute("data-flip", &moved.len().to_string());
    }
}

/// FLIP: measure, apply `change`, and on the next frame spring every element
/// that moved back from where it was.
fn flip(change: impl FnOnce()) {
    let first = flip_positions();
    change();
    request_animation_frame(move || {
        let moved = flip_positions()
            .into_iter()
            .filter_map(|(key, element, left, top)| {
                first
                    .iter()
                    .find(|(first_key, ..)| *first_key == key)
                    .map(|(_, _, first_left, first_top)| (element, first_left - left, first_top - top))
            })
            .filter(|(_, dx, dy)| *dx != 0.0 || *dy != 0.0)
            .collect::<Vec<_>>();
        flip_frame(Rc::new(moved), 0);
    });
}

#[component]
fn App() -> impl IntoView {
    let recipes: &'static [Recipe] = Box::leak(model::catalog().into_boxed_slice());
    let plan = RwSignal::new(None::<Plan>);
    let checked = RwSignal::new(Vec::<String>::new());
    let query = RwSignal::new(String::new());
    let pose = RwSignal::new("idle");
    let edit_plan = move |change: fn(&Plan) -> Plan| plan.update(|plan| *plan = plan.as_ref().map(change));

    let week_recipes = recipes;
    let week = move || {
        plan.get().map(|plan_now| {
            let days = plan_now.days.iter().map(|day| view_day(week_recipes, day, plan)).collect_view();
            view! {
                <p id="week-total">{model::week_text(week_recipes, &plan_now)}</p>
                {days}
            }
        })
    };
    let grocery_recipes = recipes;
    let grocery = move || plan.get().map(|plan_now| view_grocery(grocery_recipes, &plan_now, checked));
    let search_recipes = recipes;
    let results = Memo::new(move |_| {
        query.with(|query| {
            search_recipes
                .iter()
                .filter(|recipe| recipe.name.contains(query.as_str()))
                .map(|recipe| (recipe.name.clone(), recipe.kcal))
                .collect::<Vec<_>>()
        })
    });

    view! {
        <div id="app">
            <div class="buttons">
                <ActionButton id="plan" text="Plan my week" on:click=move |_| plan.set(Some(Plan::draw(Seed(42)))) />
                <ActionButton id="replan" text="Re-plan" on:click=move |_| edit_plan(Plan::replan) />
                <ActionButton id="move" text="Move Monday to the end" on:click=move |_| flip(move || edit_plan(Plan::rotate)) />
                <ActionButton id="pose" text="Wave" on:click=move |_| pose.update(|pose| *pose = if *pose == "idle" { "wave" } else { "idle" }) />
            </div>
            <div id="mascot" class="mascot" data-pose=move || pose.get() inner_html=MASCOT_SVG></div>
            <div id="week">{week}</div>
            <div id="grocery">{grocery}</div>
            <div id="search">
                <input id="search-input" type="search" prop:value=query.get_untracked() on:input=move |event| query.set(event_target_value(&event)) />
                <p id="search-note">{move || format!("Showing {} of {} for \"{}\"", results.with(Vec::len), model::CATALOG_SIZE, query.get())}</p>
                <ul id="results">
                    {move || results.get().into_iter().map(|(name, kcal)| view! {
                        <li class="result">
                            <span class="name">{name}</span>
                            <span class="kcal">{format!("{kcal} kcal")}</span>
                            <button class="add">"Add"</button>
                        </li>
                    }).collect_view()}
                </ul>
            </div>
        </div>
    }
}

#[wasm_bindgen(start)]
pub fn start() {
    console_error_panic_hook::set_once();
    leptos::mount::mount_to_body(App);
}
