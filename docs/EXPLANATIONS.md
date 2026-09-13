# Clear teaching and biblical authority

User decision, September 9, 2026: make explanations easier to understand, like a very clear teacher. Keep the Bible as the sole final authority for spiritual and doctrinal claims. Consider outside sources as fallible human perspectives. Seek fairness across Christian interpretations without pretending the app has no theological foundation or interpretive assumptions.

User clarification: context must always govern the use of Scripture. Never cherry-pick verses to make an argument. Establish meaning from the surrounding passage, book, original setting, and relevant wider biblical teaching before drawing a conclusion. Apply this even when the user requests support for a predetermined position. When the available excerpt lacks necessary context, seek the missing evidence or explicitly limit the conclusion.

User clarification, September 10, 2026: weave the biblical basis throughout each substantive answer. Start with a verse or short passage, explain it immediately in context, then introduce and explain another passage when needed. Do not leave supporting Scripture in a list at the end. Verified quotations retain the existing quotation-card format; when ESV evidence is missing, use a clearly identified paraphrase with its reference beside the explanation. One passage can be sufficient, and greetings and simple follow-ups remain brief.

## First response in each conversation

User decision, September 13, 2026: start the first model response in a thread with a reminder that Christian growth involves prayer, sanctification, and counsel from other believers. The app must not replace these parts of Christian life. Invite the user to pray for God's guidance before continuing; follow-up responses omit the reminder.

The [conversation-opening guidance](../backend/src/conversation-opening.ts) supplies this opening paragraph:

> Growing as a Christian includes seeking answers through prayer, sanctification (becoming more like Christ), and counsel from other believers. Please don't let this app replace these essential parts of your Christian life. Before we continue, take a moment to pray and ask God to reveal His truth and guide your understanding.

The backend selects the first-response instruction when the full request history contains no assistant message. Existing and reopened threads with an assistant reply receive an explicit instruction to omit the preamble, even if the older reply predates this change. Retrying an unanswered first question retains the reminder; a new thread starts fresh. No account-wide flag or client schema change is needed.

For allowed responses, the preamble comes before Scripture or a greeting. The model then answers in the same response, using the existing passage-and-explanation flow for substantive questions. It must not wait for prayer confirmation, require belief, promise immediate revelation, or portray its answer as God's words. Normal discussion of prayer and Christian growth remains appropriate in follow-ups when the question calls for it. Off-topic, unsafe, and crisis responses retain their existing server-provided messages.

Both JSON and streaming requests receive the selected instruction, and the reservation estimate includes it. This is generation guidance, not a server-inserted paragraph. Mocked integration checks verify prompt selection and preserved history; live model adherence still needs a requested live evaluation.

Validation: `./scripts/dev check` passed Bible index consistency, TypeScript, all 379 backend tests, both recovery script tests, and the deployment dry run. Logs are under `.dev/logs/` for run `20260913-162907-54970`; backend tests: `backend-tests-20260913-162908-54970.log`. `git diff --check` passed. This change has not been deployed or evaluated with paid inference. No iOS tests or simulator UI automation were run.

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
