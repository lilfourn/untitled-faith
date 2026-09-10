# Reliability operations

## Release checks

Run `./scripts/dev check` and `./scripts/dev build`. `./scripts/dev build-tests`
also compiles the signed app, unit tests, and UI tests without launching a
simulator. Running iOS tests or simulator automation still requires Luke's
explicit request. The backend GitHub Actions workflow runs the same backend
checks on pull requests and main pushes, without deployment credentials or
live inference. Its first hosted execution remains to be verified after push.

Apply migration `0007_recovery.sql` before deploying the recovery Worker.
The shared checkout also contains payment work using migration 0008; deploy
only a reviewed, coherent revision with all of its required migrations.
Do not deploy a moving shared working directory while another agent is editing it.
Use the existing release procedures in `backend/DEPLOYMENT.md` and `docs/TESTFLIGHT.md`.
Deploy the backend before distributing the new client: retry status uses a new route.

`GET /health` is public liveness. `GET /v1/readiness` requires a valid app session
and active account; it checks required configuration presence and recovery schema
access without calling Apple, inference, or payment providers. It does not prove
that those external providers are working or that every credential is valid.
`GET /v1/answers/status/{idempotency-key}` is also authenticated and returns only
the caller's attempt status. It never returns prompts or generated answers.

## Interrupted usage

The scheduled reconciler runs every 15 minutes. A reservation older than five
minutes is released automatically only when its durable checkpoint proves no
provider call started. Other interrupted work remains uncertain until accounting
can be verified. Eight unsuccessful reconciliation attempts or an age of 24 hours
marks a request for operator review. No provider ID is a supported review case.

Configure the operational alert destination to watch `usage_recovery_required`
and `deletion_recovery_required`; acknowledge these within one day. The code emits
these events, but alert delivery is not configured by adding this document.
Also monitor `request_failed`, final `answer_stream_completed` status/errorCode,
and answer duration. An initial SSE HTTP 200 is not proof of a successful answer.
Existing logs and sampled traces are enabled in Wrangler.

Use the recovery tool from the repository root:

```sh
node backend/scripts/usage-recovery.mjs --list --remote
node backend/scripts/usage-recovery.mjs --inspect REQUEST_UUID --remote
```

For a verified provider generation, preview a resolution with the actual integer
cash cost in micro-USD and its token counts. Cost includes the provider acquisition
fee as defined by `cashCostMicros`. The supplied values describe the outstanding
generation only; the database adds any checkpointed review cost exactly once.

```sh
node backend/scripts/usage-recovery.mjs \
  --request REQUEST_UUID --kind verified \
  --cost-micros 2110 --prompt-tokens 100 --completion-tokens 200 \
  --reason 'Verified provider generation and final usage record' --operator Luke
```

The command above only prints SQL. After reviewing the evidence and SQL, add
`--apply` to write locally, or `--apply --remote` to resolve a production request.
Use a real request UUID in place of `REQUEST_UUID`. Keep credentials and chat text
out of the reason field. The tool invokes the project-local Wrangler with argument
arrays rather than shell interpolation, and requires explicit production selection.

When provider cost cannot be established, an intentional operator decision can use
`--kind write_off` with zero cost and zero tokens and a reason explaining why.
This absorbs the unknown generation's cost rather than asserting it was free;
known review cost remains accounted. This does not refund a previously settled
request or automatically restore its free-question counter. Ordinary refunds are
a separate workflow. Never fabricate usage to release a hold.

The audit insert and settlement are atomic. Duplicate/racing resolutions fail
without another charge. After an ambiguous command failure, inspect the request
before retrying. `usage_resolutions` records the reason, operator, and amounts.
The phone shows when unresolved usage needs support, including older months.

## Account deletion

The device stores a pending deletion record in device-only Keychain before
requesting server deletion. It persists server confirmation before local cleanup,
and resumes on restart/activation or explicit retry. Cleanup uses the original
account/backend namespace and does not clear another account's saved session.

The server accepts a valid sealed deletion credential again when the original
account is already gone. It records Apple's successful revocation so scheduled
cleanup can finish a failed database delete. Before that checkpoint, a client
retry can repeat revocation; Apple documents successful responses for tokens that
were already invalidated. See [Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).

An account with outstanding funding, unresolved usage, or a payable checkout
cannot be deleted until that state is resolved. If a deletion cannot reach Apple
before its renewal credential expires, support must resolve it; never bypass
identity verification or silently clear a pending deletion record. Overdue server
deletion intents emit `deletion_recovery_required`.

## Rollback and restore rehearsal

Before a production release, record its source revision, Worker version, applied
migrations, and a D1 Time Travel bookmark. Rehearse against an isolated staging
Worker/database using synthetic accounts and test payments. Checkpoint an account,
settle a request, inject a failed response, verify recovery, then rehearse restoring
the staging database and its compatible Worker revision.

Worker rollback does not roll back database data. Migration 0007 is additive;
avoid reversing it merely to roll back Worker code. Review other migrations in the
release independently. A database restore can rewind financial records, so pause
new writes and reconcile external transactions before reopening a restored service.
Never rehearse a restore on the production database.

Consult the installed CLI help and current [Wrangler D1 commands](https://developers.cloudflare.com/workers/wrangler/commands/d1/),
[D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/), and
[Worker rollback limitations](https://developers.cloudflare.com/workers/configuration/versions-and-deployments/rollbacks/)
before an actual operation. This implementation did not provision staging, set
remote alerts, restore a database, or deploy a Worker. One diagnostic reproduction
of the reported Paul question used provider credits; a full live quality evaluation
has not been run.
