import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { buildReport, renderReport, listAll, LIVE_ACCOUNT, usd } from './payment-report-core.mjs';
import { parseOptions } from './payment-report.mjs';

const september = Date.parse('2026-09-13T12:00:00Z');
const october = Date.parse('2026-10-01T12:00:00Z');
const sql = readFileSync(new URL('./payment-report.sql', import.meta.url), 'utf8');
function database() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of readdirSync(migrations).filter(name => name.endsWith('.sql')).sort()) {
    db.exec(readFileSync(new URL(file, migrations), 'utf8'));
  }
  db.exec(`INSERT INTO users(id, identity_hash, app_account_token, created_at) VALUES ('buyer', 'identity', 'token', ${september});
    INSERT INTO free_months(month, budget_micros) VALUES ('2026-09', 63300000);
    INSERT INTO checkout_intents(id, user_id, idempotency_key, amount_cents, developer_share_bps, estimated_fee_cents,
      livemode, session_id, status, created_at, checked_at)
    VALUES ('intent', 'buyer', 'key', 1000, 300, 59, 1, 'cs_1', 'paid', ${september}, ${september});
    INSERT INTO stripe_payments(id, intent_id, user_id, charge_id, gross_cents, fee_cents, fee_confirmed,
      refunded_cents, disputed, dispute_open, usage_micros, developer_micros, created_at, checked_at)
    VALUES ('pi_1', 'intent', 'buyer', 'ch_1', 1000, 59, 1, 0, 0, 0, 9110000, 300000, ${september}, ${september});`);
  return db;
}
function input(db) {
  const transaction = { id: 'txn_1', amount: 1000, fee: 59, net: 941, currency: 'usd',
    source: 'ch_1', type: 'charge', created: september / 1000, balance_type: 'payments' };
  return { account: { id: LIVE_ACCOUNT, default_currency: 'usd' },
    balance: { livemode: true, available: [{ currency: 'usd', amount: 0 }], pending: [{ currency: 'usd', amount: 941 }] },
    ledger: JSON.parse(db.prepare(sql).get().snapshot), transactions: [transaction],
    charges: [{ id: 'ch_1', payment_intent: 'pi_1', amount: 1000, amount_refunded: 0, currency: 'usd',
      paid: true, captured: true, status: 'succeeded', disputed: false, livemode: true,
      metadata: { application: 'untitled-faith', intent_id: 'intent' }, balance_transaction: transaction }],
    startedAt: new Date(september).toISOString(), finishedAt: new Date(september).toISOString() };
}
function spend(db, funding, cost, status = 'settled') {
  const request = `${funding}-${cost}`;
  db.exec(`INSERT INTO usage_requests(id, user_id, idempotency_key, month, day, created_at, updated_at,
    funding, status, reserved_micros, free_daily_limit, free_monthly_limit)
    VALUES ('${request}', 'buyer', '${request}', '2026-09', '2026-09-13', ${september}, ${september},
      '${funding}', 'reserved', 500000, 30, 30);`);
  if (status !== 'reserved') db.exec(`UPDATE usage_requests SET status = '${status}', cost_micros = ${cost} WHERE id = '${request}'`);
}

test('real migrations: $10 splits to usage $9.11, developer $0.30, fees $0.59; spend stays exact', () => {
  const db = database();
  try {
    spend(db, 'paid', 91);
    spend(db, 'free', 6000);
    const r = buildReport(input(db));
    assert.equal(r.status, 'matched');
    assert.equal(r.allocations.totalUsageFundingMicros, 9_110_000);
    assert.equal(r.allocations.totalDeveloperShareMicros, 300_000);
    assert.equal(r.usage.positiveUserBalancesMicros, 9_109_909);
    assert.equal(r.usage.freeSpentMicros, 6000);
    assert.equal(r.months[0].paidUsageSpentMicros, 91);
    assert.match(renderReport(r), /\$9\.109909/);
    assert.equal(JSON.stringify(r).includes('identity'), false);
  } finally { db.close(); }
});

test('reservations remain within the balance, and unsettled usage is visible', () => {
  const db = database();
  try {
    spend(db, 'paid', 0, 'reserved');
    const r = buildReport(input(db));
    assert.equal(r.usage.reservedMicros, 500_000);
    assert.equal(r.usage.remainingLedgerMicros, 9_110_000);
    assert.ok(r.issues.some(i => i.code === 'unsettledUsage'));
  } finally { db.close(); }
});

test('partial refund adjusts both allocations in the refund month', () => {
  const db = database();
  try {
    db.exec(`UPDATE stripe_payments SET refunded_cents = 500, usage_micros = 4260000,
      developer_micros = 150000, revision = 2, checked_at = ${october}`);
    const data = input(db);
    data.charges[0].amount_refunded = 500;
    data.transactions.push({ id: 'txn_refund', amount: -500, fee: 0, net: -500, currency: 'usd', type: 'refund', created: october / 1000 });
    data.balance.pending[0].amount = 441;
    const r = buildReport(data);
    assert.equal(r.status, 'matched');
    assert.equal(r.allocations.totalDeveloperShareMicros, 150000);
    assert.equal(r.months[0].month, '2026-10');
    assert.equal(r.months[0].usageFundingMicros, -4_850_000);
    assert.equal(r.months[1].usageFundingMicros, 9_110_000);
  } finally { db.close(); }
});

test('full refund leaves retained fees as a separate expense, never negative developer allocation', () => {
  const db = database();
  try {
    spend(db, 'paid', 100_000);
    db.exec(`UPDATE stripe_payments SET refunded_cents = 1000, usage_micros = 0,
      developer_micros = 0, revision = 2, checked_at = ${october}`);
    const data = input(db);
    data.charges[0].amount_refunded = 1000;
    data.transactions.push({ id: 'txn_refund', amount: -1000, fee: 0, net: -1000, currency: 'usd', type: 'refund', created: october / 1000 });
    data.balance.pending[0].amount = -59;
    const r = buildReport(data);
    assert.equal(r.allocations.totalDeveloperShareMicros, 0);
    assert.equal(r.stripeCash.cashOutsideAllocationsMicros, -590000);
    assert.equal(r.usage.negativeUserBalancesMicros, -100000);
    assert.ok(r.issues.some(i => i.code === 'negative_user_balances'));
    assert.equal(r.issues.some(i => i.code === 'wallet_ledger_mismatch'), false);
  } finally { db.close(); }
});

test('payouts and their reversals move combined cash without reducing developer earnings', () => {
  const db = database();
  try {
    const data = input(db);
    data.transactions.push({ id: 'txn_out', amount: -900, fee: 0, net: -900, currency: 'usd', type: 'payout', created: september / 1000 });
    data.balance.pending[0].amount = 41;
    let r = buildReport(data);
    assert.equal(r.status, 'matched');
    assert.equal(r.allocations.totalDeveloperShareMicros, 300000);
    assert.equal(r.stripeCash.payoutNetMicros, -9000000);
    data.transactions.push({ id: 'txn_return', amount: 900, fee: 0, net: 900, currency: 'usd', type: 'payout_failure', created: september / 1000 });
    data.balance.pending[0].amount = 941;
    r = buildReport(data);
    assert.equal(r.status, 'matched');
    assert.equal(r.stripeCash.payoutNetMicros, 0);
  } finally { db.close(); }
});

test('deleted-account funding is retained for review and not reclassified as developer earnings', () => {
  const db = database();
  try {
    db.exec("DELETE FROM users WHERE id = 'buyer'");
    const r = buildReport(input(db));
    assert.equal(r.usage.detachedBalanceMicros, 9110000);
    assert.equal(r.allocations.totalDeveloperShareMicros, 300000);
    assert.ok(r.issues.some(i => i.code === 'deleted_account_balance_requires_review'));
    assert.equal(r.issues.some(i => i.code === 'wallet_ledger_mismatch'), false);
  } finally { db.close(); }
});

test('missing payments, fee delays, allocation drift, and concurrent cash changes require review', () => {
  const db = database();
  try {
    const missing = input(db);
    missing.ledger.payments = [];
    assert.ok(buildReport(missing).issues.some(i => i.code === 'stripe_payment_missing_from_ledger'));
    const absent = input(db);
    absent.charges = [];
    assert.ok(buildReport(absent).issues.some(i => i.code === 'ledger_payment_missing_from_stripe'));
    const delayed = input(db);
    delayed.ledger.payments[0].feeConfirmed = 0;
    assert.ok(buildReport(delayed).issues.some(i => i.code === 'fee_reconciliation_pending'));
    const drift = input(db);
    drift.ledger.payments[0].allocatedDeveloperMicros--;
    drift.balance.pending[0].amount++;
    assert.ok(buildReport(drift).issues.some(i => i.code === 'allocation_ledger_mismatch'));
    assert.ok(buildReport(drift).issues.some(i => i.code === 'stripe_balance_changed_or_not_reconciled'));
  } finally { db.close(); }
});

test('won disputes restore allocations while unresolved disputes require review', () => {
  const db = database();
  try {
    const data = input(db);
    data.charges[0].disputed = true;
    data.disputes = { ch_1: [{ status: 'won' }] };
    assert.equal(buildReport(data).status, 'matched');
    data.disputes.ch_1[0].status = 'needs_response';
    assert.ok(buildReport(data).issues.some(i => i.code === 'open_dispute'));
    data.disputes = {};
    assert.ok(buildReport(data).issues.some(i => i.code === 'dispute_status_unknown'));
  } finally { db.close(); }
});

test('wrong account, mixed mode, unsafe money, and non-USD settlement fail closed', () => {
  const db = database();
  try {
    for (const modify of [d => { d.account.id = 'acct_gridbloom'; }, d => { d.balance.livemode = false; },
      d => { d.ledger.livemode = 0; }, d => { d.account.default_currency = 'eur'; },
      d => { d.ledger.usage.paidSpentMicros = Number.MAX_SAFE_INTEGER + 1; },
      d => { d.balance.pending[0].currency = 'eur'; }, d => { d.transactions[0].currency = 'jpy'; }]) {
      const data = input(db); modify(data); assert.throws(() => buildReport(data));
    }
    assert.throws(() => usd(NaN));
    assert.equal(usd(Number.MAX_SAFE_INTEGER), '$9007199254.740991');
    assert.equal(usd(-590000), '-$0.59');
    assert.equal(usd(300000), '$0.30');
    assert.throws(() => parseOptions(['--apply']));
    assert.throws(() => parseOptions(['--json', '--json']));
  } finally { db.close(); }
});

test('empty production ledger reports zero without inventing money', () => {
  const db = database();
  try {
    db.exec('DELETE FROM payment_allocations; DELETE FROM stripe_payments; DELETE FROM checkout_intents; DELETE FROM users;');
    const data = input(db);
    data.charges = []; data.transactions = []; data.balance.pending[0].amount = 0;
    assert.equal(buildReport(data).status, 'matched');
    assert.equal(buildReport(data).allocations.totalDeveloperShareMicros, 0);
  } finally { db.close(); }
});

test('Stripe lists follow every cursor and reject incomplete or repeated pages', async () => {
  const calls = [];
  const items = await listAll(async (path, args) => {
    calls.push({ path, args });
    return calls.length === 1 ? { data: [{ id: 'a' }], has_more: true } : { data: [{ id: 'b' }], has_more: false };
  }, '/v1/charges', ['-d', 'created[lte]=100']);
  assert.deepEqual(items.map(item => item.id), ['a', 'b']);
  assert.deepEqual(calls[1].args.slice(-2), ['--starting-after', 'a']);
  assert.ok(calls.every(call => call.args.includes('created[lte]=100')));
  await assert.rejects(listAll(async () => ({ data: [], has_more: true }), '/v1/charges'));
  await assert.rejects(listAll(async () => ({ data: [{ id: 'a' }], has_more: true }), '/v1/charges'));
  await assert.rejects(listAll(async () => ({ error: {} }), '/v1/charges'));
});
