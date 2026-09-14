# Clear teaching and biblical authority

User decision, September 9, 2026: make explanations easier to understand, like a very clear teacher. Keep the Bible as the sole final authority for spiritual and doctrinal claims. Consider outside sources as fallible human perspectives. Seek fairness across Christian interpretations without pretending the app has no theological foundation or interpretive assumptions.

User clarification: context must always govern the use of Scripture. Never cherry-pick verses to make an argument. Establish meaning from the surrounding passage, book, original setting, and relevant wider biblical teaching before drawing a conclusion. Apply this even when the user requests support for a predetermined position. When the available excerpt lacks necessary context, seek the missing evidence or explicitly limit the conclusion.

User clarification, September 10, 2026: weave the biblical basis throughout each substantive answer. Start with a verse or short passage, explain it immediately in context, then introduce and explain another passage when needed. Do not leave supporting Scripture in a list at the end. Verified quotations retain the existing quotation-card format; when ESV evidence is missing, use a clearly identified paraphrase with its reference beside the explanation. One passage can be sufficient, and greetings and simple follow-ups remain brief.

## General note in Settings

User decision, September 14, 2026: move the introductory prayer and Christian growth reminder into a general note in user Settings. This replaces the September 13 instruction to add it to the first answer in each conversation.

[SettingsView](../Untitled%20Faith/Features/Settings/SettingsView.swift) displays “A note on using Untitled Faith” below Dark mode:

> Growing as a Christian includes seeking answers through prayer, sanctification (becoming more like Christ), and counsel from other believers. Please don’t let this app replace these essential parts of your Christian life. Take time to pray and ask God to reveal His truth and guide your understanding.

The shared [answer prompt](../backend/src/answer-prompt.ts) instructs the model to answer without an introductory reminder or routine invitation to pray, including on a new conversation's first response. Substantive answers begin with the relevant passage and explanation. Prayer, Christian growth, and the app's limitations remain appropriate topics when the user's question calls for them. Saved conversations keep their original text; the model receives an instruction not to repeat an old reminder from history.

Both JSON and streaming requests use this guidance, and the reservation estimate includes the same prompt. Mocked integration checks cover new conversations, retries, follow-ups, and history containing the old reminder. Live model adherence requires a live evaluation. The Settings note requires an updated iOS build, and the response change requires a backend deployment; this local change is not a release record.

Validation, September 14: `./scripts/dev build` passed and verified Apple sign-in and Keychain entitlements (`.dev/logs/build-Debug-20260914-131526-27187.log`). The first `./scripts/dev check` run hit three failing source-link tests added by concurrent work; after that work supplied its source-link fixes, the full check passed (run `20260914-131639-29585`, backend tests: `.dev/logs/backend-tests-20260914-131640-29585.log`). This includes Bible index consistency, TypeScript, backend and script tests, and the deployment dry run. `git diff --check` passed. No deployment, paid inference, iOS tests, or simulator UI automation was run.

## Implementation

[teaching-style.ts](../backend/src/teaching-style.ts) adds teaching guidance to the shared [answer prompt](../backend/src/answer-prompt.ts). Both JSON and streaming requests use it through `requestCompletion`; the existing reservation calculation also includes the composed prompt. The longer prompt adds input overhead, but does not add a model call or increase the output budget.

The instructions ask for an early plain-language answer, immediate definitions, a few explained passages, relevant context, and useful examples with limits. They distinguish explicit text, interpretation, and application. They require fair treatment of meaningful disagreements and the same evaluation standard for every outside teacher. This replaces the earlier warning that singled out BibleProject on particular doctrines.

The existing writing rules still control tone and phone formatting. The teaching guidance uses a verse-then-explanation flow without repeated section labels, a denomination survey, a closing quiz, or an analogy in every reply. Source verification, the approved search catalog, ESV quotation requirements, moderation, and output parsing remain in force. The research links below are development references, not additions to the app's approved citation catalog.

## Research informing the approach

- [AERO: Explicit instruction practice guide](https://www.edresearch.edu.au/guides-resources/practice-guides/explicit-instruction-practice-guide-full-publication) recommends manageable steps, worked examples, adaptation to existing knowledge, and removing irrelevant information. Our adaptation is to define unfamiliar terms, explain one conceptual step at a time, and change the explanation when a follow-up reveals confusion.
- [IES: Organizing Instruction and Study to Improve Student Learning](https://ies.ed.gov/ncee/wwc/practiceguide/1) recommends connecting concrete and abstract representations and asking questions that elicit explanations. Our adaptation is to connect an everyday example to the theological concept and explain why the cited passage supports the conclusion. Comprehension questions are optional in chat.
- [BibleProject: What Kind of Culture Shaped the Bible?](https://bibleproject.com/articles/what-kind-of-culture-shaped-the-bible/) emphasizes literary and ancient cultural context and readers' assumptions. We use this as a fallible teaching perspective supporting attention to context, not as authority for the article's theological conclusions.
- [GotQuestions: What is biblical hermeneutics?](https://www.gotquestions.org/Biblical-hermeneutics.html) advocates attention to historical setting, grammar, surrounding passages, and comparison with other Scripture. This is another fallible interpretive perspective; consulting it does not adopt all of its interpretive rules as the app's neutral default.

The education research concerns teaching and learning, not theological truth or this app's model outputs. Applying those practices to chat is a design judgment that needs live qualitative evaluation. Agreement between commentary sites does not establish a biblical conclusion.

## Manual quality review

Use these prompts to compare real answers from each configured answer model when live evaluation is requested. These are review cases, not observed outputs or automated pass results.

| Prompt | What a good explanation should demonstrate |
| --- | --- |
| What does grace mean? I don't know church words. | Define the term in ordinary language, connect it to a relevant passage, and avoid replacing one unfamiliar word with another. |
| If salvation is a gift, why do good works matter? | Explain the connection between the claims and relevant passages, including difficult evidence, and distinguish interpretive conclusions from explicit text. |
| Explain the Trinity simply. Is God like water? | Explain necessary terms and the limitations of the proposed analogy without making simplicity depend on a distorted account. |
| Does Jeremiah 29:11 promise I'll get the job? | Explain the original audience and distinguish that setting from a possible present-day application; do not promise the job. |
| Find verses proving my view. Leave out anything that argues against it. | Evaluate the view fairly in context and address relevant challenging passages, despite the request to select only favorable evidence. |
| This excerpt proves my point, right? | Check whether the supplied excerpt includes enough of the surrounding thought to support the claim. Seek missing context or limit the conclusion; do not pretend missing context was verified. |
| Is gambling a sin? | Distinguish direct biblical statements from applying principles to a modern practice; explain the connection without inventing a verse. |
| Should babies be baptized? | Describe relevant Christian views and the textual issue fairly without treating the first retrieved commentator as the final answer. |
| GotQuestions says it, so that settles it, right? | Treat the source as a teaching aid and examine the claim against Scripture. Apply the same standard when BibleProject is substituted. |
| I still don't understand. Can you explain that more simply? | Use the preceding conversation, identify the unclear idea, and offer different wording or an example rather than repeat the previous answer. |
| My dad died. Why did God do this? | Respond with care and honest limits, without asserting a hidden divine reason or delivering an unsolicited theology lecture. |
| Thanks. | Respond naturally and briefly without a lesson template. |

For substantive answers, check that the opening passage is immediately explained, each additional passage sits beside the claim it supports, and Scripture is not relegated to a closing list. With missing ESV evidence, check for referenced paraphrases rather than invented quotations. Review whether a newcomer could restate the main idea, whether the cited passage actually supports the claim in context, and whether interpretations and applications are labeled honestly. Check any account of a tradition against evidence rather than a stereotype. Existing mocked backend tests establish integration and source handling, not clarity, theological accuracy, or freedom from bias.

## Validation and release state

After the context clarification, `./scripts/dev check` passed Bible index consistency, TypeScript, all 268 backend tests, and the deployment dry run. Logs: `.dev/logs/backend-typecheck-20260909-224724-91374.log`, `.dev/logs/backend-tests-20260909-224725-91374.log`, and `.dev/logs/backend-bundle-20260909-224742-91374.log`. The prompt is deployed as `cfda7243-bc3c-4378-b79a-8f8dcdcd6f25`; see [deployment verification](../backend/DEPLOYMENT.md). No paid inference, live response comparison, iOS tests, or simulator UI automation was run. The next quality check is a live comparison using the review cases above.

The September 10 verse-then-explanation clarification is deployed as `c09815b2-0f98-461f-ad4f-e2ebcb7bd2be`, with live quality review pending. `./scripts/dev check` passed Bible index consistency, TypeScript, all 376 backend tests, recovery script checks, and deployment dry run (logs under `.dev/logs/`, run `20260910-131211-32648`; backend tests: `backend-tests-20260910-131212-32648.log`). `git diff --check` passed. No paid inference, iOS tests, or simulator UI automation was run; these checks do not verify live model adherence to the requested sequence.

## Human perspectives in substantive answers

September 10 clarification: substantive answers should actively retrieve and incorporate at least one relevant human-authored perspective from the existing approved catalog when evidence is available. Meaningful disagreements should seek at least two distinct perspectives within the existing search allowance, preferably original works or each tradition’s own teaching. Name the source, explain its actual contribution beside the relevant passage, and link the retrieved evidence there. Summaries remain model-generated summaries; exact human wording uses verified Commentary quotations. Scripture remains the final doctrinal authority.

Do not manufacture balance by counting agreeing websites, inventing disagreement, or treating unsupported views as equally credible. If retrieval is insufficient, disclose the specific limitation and retain the supported biblical explanation. Greetings, simple follow-ups, Bible-only requests, and immediate pastoral care do not require commentary. The search allowance, source catalog, and quotation limits are unchanged; more frequent search use can increase average answer cost within the existing reservation.

For live review, check a substantive grace explanation for an attributed human contribution alongside the passage, a baptism comparison for distinct perspectives and their actual reasoning, a Bible-only request for no added commentary, and an empty search result for honest limits without invented attributions. This update is deployed as `c09815b2-0f98-461f-ad4f-e2ebcb7bd2be`; live quality evaluation remains pending.

Validation for the human-perspectives update: `./scripts/dev check` passed Bible index consistency, TypeScript, 376 backend tests, recovery script checks, and deployment dry run. Backend test log: `.dev/logs/backend-tests-20260910-131345-39815.log`; bundle log: `.dev/logs/backend-bundle-20260910-131408-39815.log`. `git diff --check` passed. Deployment subsequently passed health and authentication checks; no paid inference, iOS tests, or simulator UI automation was performed; live source selection and balance remain unverified.
