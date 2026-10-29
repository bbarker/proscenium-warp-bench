//! The scaling benchmark: `generated.rs` is written by
//! `nu bench/frontend-wasm/gen-cards.nu <count>`, with its Unison twin under
//! `bench.cards.s<count>`.

use wasm_bindgen::prelude::wasm_bindgen;

mod generated;

#[wasm_bindgen(start)]
pub fn start() {
    console_error_panic_hook::set_once();
    leptos::mount::mount_to_body(generated::App);
}
