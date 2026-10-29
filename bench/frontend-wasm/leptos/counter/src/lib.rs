//! The smallest benchmark UI: one button and a count, the fixed cost of the
//! framework. Its Unison twin is `bench.counter.ui`.

use leptos::prelude::*;
use wasm_bindgen::prelude::wasm_bindgen;

#[component]
fn App() -> impl IntoView {
    let (count, set_count) = signal(0u64);
    view! {
        <div id="app">
            <button id="inc" on:click=move |_| set_count.update(|count| *count += 1)>"+1"</button>
            <span id="count">{move || count.get().to_string()}</span>
        </div>
    }
}

#[wasm_bindgen(start)]
pub fn start() {
    console_error_panic_hook::set_once();
    leptos::mount::mount_to_body(App);
}
