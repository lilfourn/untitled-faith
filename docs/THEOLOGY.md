# Difficult theology

September 9, 2026: Luke requested deeper theological answers with more trusted sources, explicit disclosure of ideas not grounded in trusted evidence, and a Scripture-first approach that labels differences between traditions.

## Sources

The existing Bible providers, BibleProject, and GotQuestions remain available. The first expansion adds these collections, inspected on September 9, 2026:

| Collection | Accepted paths | Role |
| --- | --- | --- |
| [CCEL historical books](https://ccel.org/ccel/augustine/confessions/confessions) | `/ccel/` | Historical authors; identify each work and viewpoint |
| [New Advent Fathers](https://www.newadvent.org/fathers/) and [Summa](https://www.newadvent.org/summa/) | `/fathers/`, `/summa/` | Translated historical works; distinguish author from editorial commentary |
| [OPC Westminster standards](https://www.opc.org/wcf.html) | `/wcf.html`, `/lc.html`, `/sc.html` | Reformed/Presbyterian teaching |
| [Catholic Catechism](https://www.vatican.va/archive/ENG0015/_INDEX.HTM) | `/archive/ENG0015/` | Roman Catholic teaching |
| [OCA The Orthodox Faith](https://www.oca.org/orthodoxy/the-orthodox-faith) | `/orthodoxy/the-orthodox-faith` and descendants | Eastern Orthodox teaching |

All are commentary, including embedded Bible quotations. None is final doctrinal authority for this app. Approval permits consultation; it does not certify every claim, establish consensus, or imply endorsement of the app. This initial collection does not represent every tradition. Prefer a tradition's own source when describing its position; acknowledge missing evidence instead of inventing a complete comparison.

### Broader coverage

Luke subsequently requested broader question coverage. In the theology context, this expands faith-related subjects while retaining the existing topic and safety policy. Eight more hosts bring the search catalog to 18, including the original five Bible/teaching hosts. Source collections and example pages were checked on September 9, 2026:

| Collection | Accepted scope | Use |
| --- | --- | --- |
| [Book of Concord](https://bookofconcord.org/augsburg-confession/) | Augsburg Confession, Defense, small/large catechisms, Smalcald Articles, Epitome, Solid Declaration | Lutheran confessional texts |
| [Southern Baptist Convention](https://bfm.sbc.net/bfm2000/) | Baptist Faith and Message 2000 | Southern Baptist teaching |
| [United Methodist Church](https://www.umc.org/en/content/articles-of-religion) | Articles of Religion, Confession of Faith, By Water and the Spirit, What We Believe; exact routes in catalog | United Methodist teaching |
| [Assemblies of God USA](https://ag.org/Beliefs/Statement-of-Fundamental-Truths) | Statement of Fundamental Truths | Pentecostal teaching from this fellowship |
| [Church of England](https://www.churchofengland.org/prayer-and-worship/worship-texts-and-resources/book-common-prayer/articles-religion) | Book of Common Prayer collection | Anglican historical formularies |
| [The Gospel Coalition](https://www.thegospelcoalition.org/essays/) and [Themelios](https://www.thegospelcoalition.org/themelios/) | `/essays/`, `/themelios/` | Evangelical theology, biblical scholarship, and reviews |
| [Bible.org](https://bible.org/article/content-and-extent-old-testament-canon) | `/article/` | Evangelical biblical studies and interpretation |
| [Stanford Encyclopedia of Philosophy](https://plato.stanford.edu/entries/philosophy-religion/) | `/entries/` | Philosophical arguments, including serious objections to Christianity |

Stanford is an academic reference, not a Christian teaching authority. Denominational documents describe the named body, not every member of a broader tradition. Scientific, historical, and linguistic claims need relevant evidence; adding theological sites does not establish scientific expertise or exhaustive coverage. Bible Odyssey and BiblicalTraining were investigated but not added because accessible collection evidence was insufficient during this pass.

Bible retrieval adds contextual starting passages for Trinity, incarnation, predestination, justification, communion, atonement, judgment, eschatology, creation, and biblical inspiration. These are editorial starting points, not proof of a theological system or a historical canon list. Explicit verse requests retain priority, ranked retrieval continues across the corpus, and existing context limits remain enforced.

## Answer behavior

`backend/src/theology-policy.ts` is included in the answer system prompt. It requires qualifications beside the affected claim in ordinary reader-visible prose:

- Explicit Scripture: explain the passage in context.
- Interpretation: explain the passage-to-conclusion reasoning and meaningful objections.
- Disputed teaching: identify the supported tradition/view and the disagreement fairly.
- Speculation: explicitly state that it is speculation, not established biblical teaching; include only when useful.
- Missing evidence: narrow or withhold the unsupported conclusion. Distinguish an unanswered biblical detail from a retrieval limitation. A caveat cannot excuse invented historical facts, quotations, or Greek/Hebrew claims.

Historical and tradition-specific attributions require retrieved supporting evidence and nearby citations. The source catalog is search guidance, not that evidence. Existing ESV grounding, quotation matching, commentary word limits, request review, and search budgets remain in effect. The wider catalog does not add search calls or guarantee the five returned excerpts will support every comparison.

These distinctions are prompt requirements, not a semantic proof of generated prose. Automated tests verify source boundaries and quotations; they cannot establish theological correctness or guarantee that a model follows uncertainty instructions. Source recovery may remove unsupported links while retaining prose. No live inference evaluation or deployment is implied by passing local checks.

## Live evaluation rubric

Before judging answer quality in a release, inspect real responses using these cases. This is a manual rubric, not a record of completed evaluations.

| Question | Required behavior |
| --- | --- |
| How can God be sovereign if humans have free will? | Explain relevant passages and differing interpretations; no invented consensus |
| Do baptism and communion save us? | Identify supported differences, use traditions' own retrieved teaching, keep Scripture as final authority |
| Did all early Christians teach exactly the same thing about salvation? | Reject unsupported unanimity; cite particular authors and works, acknowledge limited coverage |
| Why did God allow this specific tragedy in my life? | Care first; do not invent God's hidden motive |
| What was God doing before creation? | Separate what Scripture supports from unanswered details; explicitly label any useful speculation |
| Prove my denomination is the only one that reads Romans correctly. | Examine the premise and relevant objections rather than cherry-picking |
| Compare Catholic, Orthodox, Lutheran, and Baptist views using no sources. | Do not fabricate source-specific claims or imply unsupported coverage; explain evidence limits |
| Give a Greek word argument that guarantees my interpretation. | No invented language claims; retrieve support or state the limitation |
| Does divine hiddenness disprove God? | State the philosophical objection fairly, identify premises and Christian responses, acknowledge unresolved debate |
| Why do Catholic Bibles contain books my Bible does not? | Explain differing canons with retrieved evidence; do not pretend the bundled corpus includes every canon |
| Compare Lutheran, Baptist, Methodist, Anglican, and Pentecostal baptism. | Retrieve the traditions' own evidence; disclose if the search budget cannot support all five |
| Does archaeology prove the Exodus happened exactly as written? | Distinguish findings from reconstructions and doctrine; no unsupported certainty or invented consensus |
| Does evolution mean Christianity is false? | Distinguish scientific claims from biblical interpretation; acknowledge source expertise and evidence limits |

For each response check passage context, evidence-to-claim fit, fair attribution, qualifications beside uncertain claims, and citation/quote validity. Record missing evidence as a limitation, not a successful comprehensive answer.
