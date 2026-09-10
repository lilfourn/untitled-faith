# Clear teaching and biblical authority

User decision, September 9, 2026: make explanations easier to understand, like a very clear teacher. Keep the Bible as the sole final authority for spiritual and doctrinal claims. Consider outside sources as fallible human perspectives. Seek fairness across Christian interpretations without pretending the app has no theological foundation or interpretive assumptions.

User clarification: context must always govern the use of Scripture. Never cherry-pick verses to make an argument. Establish meaning from the surrounding passage, book, original setting, and relevant wider biblical teaching before drawing a conclusion. Apply this even when the user requests support for a predetermined position. When the available excerpt lacks necessary context, seek the missing evidence or explicitly limit the conclusion.

## Implementation

[teaching-style.ts](../backend/src/teaching-style.ts) adds teaching guidance to the shared [answer prompt](../backend/src/answer-prompt.ts). Both JSON and streaming requests use it through `requestCompletion`; the existing reservation calculation also includes the composed prompt. The longer prompt adds input overhead, but does not add a model call or increase the output budget.

The instructions ask for an early plain-language answer, immediate definitions, a few explained passages, relevant context, and useful examples with limits. They distinguish explicit text, interpretation, and application. They require fair treatment of meaningful disagreements and the same evaluation standard for every outside teacher. This replaces the earlier warning that singled out BibleProject on particular doctrines.

The existing writing rules still control tone and phone formatting. The teaching guidance does not require a fixed lesson template, a denomination survey, a closing quiz, or an analogy in every reply. Source verification, the approved search catalog, ESV quotation requirements, moderation, and output parsing remain in force. The research links below are development references, not additions to the app's approved citation catalog.

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

For substantive answers, review whether a newcomer could restate the main idea, whether the cited passage actually supports the claim in context, and whether interpretations and applications are labeled honestly. Check any account of a tradition against evidence rather than a stereotype. Existing mocked backend tests establish integration and source handling, not clarity, theological accuracy, or freedom from bias.

## Validation and release state

After the context clarification, `./scripts/dev check` passed Bible index consistency, TypeScript, all 268 backend tests, and the deployment dry run. Logs: `.dev/logs/backend-typecheck-20260909-224724-91374.log`, `.dev/logs/backend-tests-20260909-224725-91374.log`, and `.dev/logs/backend-bundle-20260909-224742-91374.log`. The change is local and has not been deployed. No paid inference, live response comparison, iOS tests, or simulator UI automation was run. The next quality check is a live comparison using the review cases above.
