//! A cut of the js-framework-benchmark table (create, append, update, swap,
//! select, remove, clear), adapted from the Leptos fork's own
//! `examples/js-framework-benchmark` with `view!` in place of `template!` (the
//! app writes `view!`) and the shared generator in place of `rand`, so both
//! implementations draw the same labels. Its Unison twin is `bench.rows.ui`.

use leptos::prelude::*;
use wasm_bindgen::prelude::wasm_bindgen;

static ADJECTIVES: &[&str] = &[
    "pretty",
    "large",
    "big",
    "small",
    "tall",
    "short",
    "long",
    "handsome",
    "plain",
    "quaint",
    "clean",
    "elegant",
    "easy",
    "angry",
    "crazy",
    "helpful",
    "mushy",
    "odd",
    "unsightly",
    "adorable",
    "important",
    "inexpensive",
    "cheap",
    "expensive",
    "fancy",
];

static COLOURS: &[&str] = &[
    "red", "yellow", "blue", "green", "pink", "brown", "purple", "brown", "white", "black",
    "orange",
];

static NOUNS: &[&str] = &[
    "table", "chair", "house", "bbq", "desk", "car", "pony", "cookie", "sandwich", "burger",
    "pizza", "mouse", "keyboard",
];

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct RowData {
    id: usize,
    label: ArcRwSignal<String>,
}

/// The linear congruential generator both implementations share, and the next
/// row id.
#[derive(Clone, Copy)]
struct Generator {
    seed: u64,
    next_id: usize,
}

impl Generator {
    fn pick(&mut self, words: &[&'static str]) -> &'static str {
        self.seed = (self.seed * 1_103_515_245 + 12_345) % 2_147_483_648;
        words[((self.seed / 65_536) % words.len() as u64) as usize]
    }

    fn rows(&mut self, count: usize) -> Vec<RowData> {
        (0..count)
            .map(|_| {
                let label = [self.pick(ADJECTIVES), self.pick(COLOURS), self.pick(NOUNS)].join(" ");
                let id = self.next_id;
                self.next_id += 1;
                RowData {
                    id,
                    label: ArcRwSignal::new(label),
                }
            })
            .collect()
    }
}

#[component]
fn ActionButton(id: &'static str, text: &'static str) -> impl IntoView {
    view! { <button id=id>{text}</button> }
}

#[component]
fn App() -> impl IntoView {
    let (data, set_data) = signal(Vec::<RowData>::new());
    let (selected, set_selected) = signal(None::<usize>);
    let generator = StoredValue::new(Generator {
        seed: 42,
        next_id: 1,
    });
    let draw = move |count| generator.update_value(|generator| set_data.set(generator.rows(count)));

    let remove = move |id: usize| set_data.update(|data| data.retain(|row| row.id != id));
    let run = move |_| draw(1_000);
    let run_lots = move |_| draw(10_000);
    let add = move |_| {
        generator.update_value(|generator| {
            let mut rows = generator.rows(1_000);
            set_data.update(|data| data.append(&mut rows));
        })
    };
    let update = move |_| {
        data.with(|data| {
            data.iter()
                .step_by(10)
                .for_each(|row| row.label.update(|label| label.push_str(" !!!")))
        })
    };
    let clear = move |_| set_data.set(Vec::new());
    let swap_rows = move |_| {
        set_data.update(|data| {
            if data.len() > 998 {
                data.swap(1, 998);
            }
        })
    };
    // Moves the last row to the front and puts one new row after it: a move, and
    // an insertion whose predecessor has just moved (the Unison twin is
    // `Model.rotateInsert`; neither draws a label when there are no rows).
    let rotate = move |_| {
        if data.with_untracked(|data| !data.is_empty()) {
            generator.update_value(|generator| {
                let mut fresh = generator.rows(1);
                set_data.update(|data| {
                    if let Some(last) = data.pop() {
                        let mut rest = std::mem::take(data);
                        data.push(last);
                        data.append(&mut fresh);
                        data.append(&mut rest);
                    }
                })
            })
        }
    };
    let is_selected = Selector::new(move || selected.get());

    view! {
        <div id="app">
            <div class="buttons">
                <ActionButton id="run" text="Create 1,000 rows" on:click=run />
                <ActionButton id="runlots" text="Create 10,000 rows" on:click=run_lots />
                <ActionButton id="add" text="Append 1,000 rows" on:click=add />
                <ActionButton id="update" text="Update every 10th row" on:click=update />
                <ActionButton id="clear" text="Clear" on:click=clear />
                <ActionButton id="swaprows" text="Swap rows" on:click=swap_rows />
                <ActionButton id="rotate" text="Rotate and insert" on:click=rotate />
            </div>
            <table class="table">
                <tbody id="tbody">
                    <For
                        each=move || data.get()
                        key=|row| row.id
                        children=move |row: RowData| {
                            let row_id = row.id;
                            let label = row.label;
                            let is_selected = is_selected.clone();
                            view! {
                                <tr class:danger=move || is_selected.selected(&Some(row_id))>
                                    <td class="col-md-1">{row_id.to_string()}</td>
                                    <td class="col-md-4">
                                        <a class="lbl" on:click=move |_| set_selected.set(Some(row_id))>
                                            {move || label.get()}
                                        </a>
                                    </td>
                                    <td class="col-md-1">
                                        <a class="remove" on:click=move |_| remove(row_id)>"x"</a>
                                    </td>
                                    <td class="col-md-6"></td>
                                </tr>
                            }
                        }
                    />
                </tbody>
            </table>
        </div>
    }
}

#[wasm_bindgen(start)]
pub fn start() {
    console_error_panic_hook::set_once();
    leptos::mount::mount_to_body(App);
}
