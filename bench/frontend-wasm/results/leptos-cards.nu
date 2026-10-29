# One pass of the Leptos scaling builds (kept beside the results it wrote).
for n in [25 100 400] {
    nu bench/frontend-wasm/gen-cards.nu $n
    nu bench/frontend-wasm/bench.nu leptos cards --label $"cards-($n)-first" | ignore
    nu bench/frontend-wasm/gen-cards.nu $n --edit
    nu bench/frontend-wasm/bench.nu leptos cards --label $"cards-($n)-edit" | ignore
    nu bench/frontend-wasm/bench.nu leptos cards --dev --label $"cards-($n)-dev-first" | ignore
    nu bench/frontend-wasm/gen-cards.nu $n
    nu bench/frontend-wasm/bench.nu leptos cards --dev --label $"cards-($n)-dev-edit" | ignore
    print $"done ($n)"
}
