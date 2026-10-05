# PLAN: bulk discount
## Intent
Orders with 10 or more total units get 10% off the order total.
## Decisions
- Threshold counts total qty across items, inclusive of 10.
- Discount applies to the order total, rounded down to whole cents (integer math).
- Input is always a valid list of items per the existing contract; no validation added.
- Public signature unchanged: total_cents(items) -> int.
## Non-goals
- No config, no per-item discounts, no new modules.
## Slices
### S1 — discount
- Scope: `src/prices.py`, `tests/test_prices.py`
- Do: add discount inside total_cents.
- Wiring: none (single function).
- Acceptance: `python3 -m pytest -q tests` passes; tests cover qty 9 (no discount), 10 (discount), and rounding.
