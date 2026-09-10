# Free access and voluntary support

Planning date: September 9, 2026. The cost estimates below remain planning assumptions. Persistent accounts, free limits, personal balances, and usage accounting are now implemented; see [current account behavior](ACCOUNTS.md). Purchase checkout remains unconnected.

## User decisions

- The owner will contribute at most **$100 per month total**, including operating overhead.
- The purpose is access to answers, not profit. User contributions should be optional.
- Later decision: contributions fund the contributing user's additional usage, credited at net proceeds after fees. Personal funding carries forward between months.
- Optional developer thanks: the contributor can allocate 0–3% of their contribution to the developer. It defaults to zero and is included in the entered total. Usage receives the remainder after payment fees and this explicit share; compute pricing itself has no profit markup.
- Continue using the fixed server-side model. Users do not supply API keys or choose a model.

## Revenue assumptions

Free downloads earn no payment from Apple. Voluntary in-app support can be structured as developer tips using in-app purchase. Actual charitable fundraising has separate nonprofit approval requirements; do not present developer tips as tax-deductible donations.

The example uses Apple's standard Small Business Program terms: 15% commission after qualifying and enrolling. Enrollment is not verified here. A $5 tip therefore leaves approximately $4.25 before applicable taxes, refunds, and other adjustments; at a 30% commission it leaves $3.50. Download counts do not establish contribution rates or monthly active usage.

For example, 10,000 free downloads alone generate $0. If 100 people each give $5, that produces $500 gross and approximately $425 after a 15% commission. This is a scenario, not a forecast, and a one-time contribution does not recur monthly.

## Monthly owner-funded budget

| Allocation | USD |
| --- | ---: |
| Developer membership, $99/year amortized | 8.25 |
| Hosting allowance | 5.00 |
| Operating contingency / reserve | 20.00 |
| Cash available for OpenRouter credits including purchase fee | 66.75 |
| Total | 100.00 |

Membership is billed annually, not monthly; its initial cash payment needs provision. The entire membership is allocated to this app conservatively, even if shared with other apps. Cloudflare may fit a free tier, but the plan reserves $5 for hosting. The reserve is not profit. Future content licenses, additional services, taxes, and support costs require updating this budget.

OpenRouter charges 5.5% on credit purchases, with an $0.80 minimum. One purchase of about $63.27 in credits costs about $66.75 before any applicable tax. Pool small contributions before buying credits to avoid repeatedly paying the minimum fee.

Formula: available inference credits = (owner funding + received net contributions - fixed operating costs - reserve) / 1.055, assuming the percentage fee exceeds the minimum.

## Capacity estimates

Our one live smoke request cost $0.00136125 in inference credits. It asked for one short sentence; it is not a representative average or a basis for promising unlimited usage. Context history, retrieved sources, generated reasoning, response length, and provider pricing affect costs. The model listing currently shows promotional pricing, so the launch budget should not depend on that discount persisting.

| Assumed average inference cost per request | Requests/month with $63.27 credits |
| --- | ---: |
| $0.005 | 12,654 |
| $0.01 | 6,327 |
| $0.02 | 3,163 |

Use $0.02 as a cautious planning assumption until representative usage is measured. It is not a guaranteed maximum per request. Round the initial planning pool down to **3,000 answers/month**, equivalent to $60 of inference credits if that average holds. Including credit fees, membership, hosting, and reserve, this costs $96.55/month.

## Proposed fair-use allowance

The implemented free allowance is **up to 30 questions per month per person, with no daily cap**, subject to the shared free-access budget. The user subsequently chose personal contributed funding for usage beyond this allowance. At the full 30-question allowance, the original 3,000-answer planning pool funds 100 monthly active people. It can serve more people if average use is lower, but cannot guarantee that allowance to an unlimited audience. Actual spending is enforced by cost, not by the 3,000-answer estimate.

At 1,000 monthly active people each using 30 answers, the same cost assumption requires about $666.25/month including the reserve. Above the owner's $100, that would require approximately $666.18/month in gross tips at the assumed 15% Apple commission, before tax/refund adjustments.

A $5 tip adds about 201 answers at the 2-cent average after Apple and pooled credit fees; use **about 200** in planning. $2 adds about 80; $10 adds about 402. These are estimates, not guaranteed charitable impact claims.

The database now enforces per-user free counters and a shared $63.30 monthly cash-equivalent free pool, reserves request costs, and reconciles billed usage. Use a monthly provider-key cap as an additional operational backstop. Additional contributed funding belongs to its contributor. The original donor-funded shared-growth examples above are historical scenarios, not the current allocation policy.

## Sources

- [Apple business models](https://developer.apple.com/app-store/business-models/)
- [Apple tips and nonprofit fundraising rules](https://developer.apple.com/app-store/review/guidelines/)
- [Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Developer membership](https://developer.apple.com/programs/enroll/)
- [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [OpenRouter credit fees](https://openrouter.ai/pricing)
- [Current model pricing](https://openrouter.ai/google/gemini-3.8-flash)
- [Measured live request](../backend/DEPLOYMENT.md)
