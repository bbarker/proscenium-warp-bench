# The 1,600-card point of the Leptos scaling builds (kept beside its results).
let n = 1600
nu bench/frontend-wasm/gen-cards.nu $n
nu bench/frontend-wasm/bench.nu leptos cards --name $"cards-($n)" --label $"cards-($n)-first" | ignore
nu bench/frontend-wasm/gen-cards.nu $n --edit
nu bench/frontend-wasm/bench.nu leptos cards --name $"cards-($n)" --label $"cards-($n)-edit" | ignore
nu bench/frontend-wasm/bench.nu leptos cards --dev --name $"cards-($n)" --label $"cards-($n)-dev-first" | ignore
nu bench/frontend-wasm/gen-cards.nu $n
nu bench/frontend-wasm/bench.nu leptos cards --dev --name $"cards-($n)" --label $"cards-($n)-dev-edit" | ignore
print $"done ($n)"
