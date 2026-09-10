# Contribution wizard

The entry point is **Settings → Add usage**, available when Stripe checkout is enabled for the U.S. storefront, and in the Debug chat preview. Live Standard Checkout with Apple Pay is enabled on the separate Untitled Faith Stripe account; see [payment verification](PAYMENTS.md#verification). This is a two-step native SwiftUI flow.

1. Enter a USD contribution with a numeric keypad. Digits roll upward with `numericText` transitions; key presses have a small spring response and selection haptics. The input accepts $1–$1,000 with up to two decimal places.
2. Optionally allocate 0–3% to the developer using a slider in 0.1% steps. It starts at 0%. The bottom amount shows the developer's share. Returning to step one preserves the selected percentage and recalculates the split if the amount changes.

The user explicitly chose to take developer thanks **out of the contribution**, keeping the total unchanged. Amounts round to the nearest cent using integer arithmetic. At $10 and 3%, the total is $10 and developer thanks is $0.30. The remainder becomes usage funding after payment fees.

The final design is deliberately minimal. It has no top progress bar or header title. Step one shows “How much?”, the amount, keypad, and Next. Step two shows “Share your thanks?”, the percentage slider, developer share, and the fixed total in the Continue button. Supporting paragraphs, badges, currency captions, and the decorative summary card were removed. Controls retain accessible touch targets; number and step animations respect Reduce Motion. Colors adapt to light and dark appearance.

The thanks screen includes Luke's personal note behind a collapsed “Read developer’s note” button. It expands inline in italic text, slightly dimmed to identify it as his direct quote, and can be collapsed again. Only grammar, spelling, and punctuation were corrected; the content and attribution remain intact. Reading or hiding the note does not change the chosen percentage or contribution total.

`ContributionSelection` passes the original amount and selected share in basis points to the checkout boundary. The signed-in flow uses `StripeContributionCheckout` to open server-created Stripe Checkout in the external browser. A short explanation on the final step describes checkout and fee reconciliation. Preview mode retains `UnconfiguredContributionCheckout` and cannot charge or credit an account. The user selected Stripe with Apple Pay to retain custom amounts; there is no StoreKit purchase adapter. See [payments and separate developer accounting](PAYMENTS.md) for the server verification, owner overview, and activation state.

The backend independently validates 0–300 basis points, calculates the cent-rounded split, and records usage funding and developer thanks separately. Migration `0003_optional_developer_share.sql` preserves old zero-share behavior and reverses both allocations on refund. A duplicate transaction cannot change its selected split.

Validation covers amount entry, decimal precision, backspace and bounds, unchanged totals, cent rounding, duplicate/refunded payments, and a full native UI test in light and dark appearances. UI tests capture both steps and assert that continuing while checkout is unavailable does not show a successful payment.

Run `./scripts/dev test` for signed simulator validation and `./scripts/dev check` for backend checks. The Debug-only launch argument `--contribution-preview-dark` previews this modal in dark appearance without changing the simulator's system setting.

Verified September 9, 2026: 73 backend tests, 26 iOS unit tests, and two native UI tests passed. Migration 0003 is applied locally and in Cloudflare. Screenshots: [amount](previews/contribution-amount-minimal.png), [developer thanks](previews/developer-thanks-minimal.png), [dark appearance](previews/developer-thanks-minimal-dark.png).
