// Operational allocation report. Dollar amounts stay in integer micro-USD until display.
export const LIVE_ACCOUNT = 'acct_1UE9yV4dOZG5zTuC';
export const STRIPE_PROJECT = 'untitled-faith';
export const DATABASE_ID = '599fc9a3-1546-443b-b9bd-27dfb65c4240';

function integer(value) {
  if (!Number.isSafeInteger(value)) throw new Error('Invalid or overflowing money/count value.');
  return value;
}
const sum = values => values.reduce((total, value) => integer(total + integer(value)), 0);
const micros = cents => integer(integer(cents) * 10_000);
const id = value => typeof value === 'string' ? value : value?.id;
export function usd(value) {
  const magnitude = BigInt(Math.abs(integer(value)));
  const fraction = String(magnitude % 1_000_000n).padStart(6, '0').replace(/0+$/, '').padEnd(2, '0');
  return `${value < 0 ? '-' : ''}$${magnitude / 1_000_000n}.${fraction}`;
}

export function verifyScope(account, balance, ledger) {
  if (account.id !== LIVE_ACCOUNT) throw new Error('Wrong Stripe account; expected the separate Untitled Faith live account.');
  if (account.default_currency !== 'usd' || balance.livemode !== true || ledger.livemode !== 1) {
    throw new Error('Expected live Stripe, live D1, and USD settlement.');
  }
}

export async function listAll(get, path, params = []) {
  const items = [], seen = new Set();
  let cursor;
  for (let page = 0; page < 10_000; page++) {
    const result = await get(path, ['--limit', '100', ...params, ...(cursor ? ['--starting-after', cursor] : [])]);
    if (!Array.isArray(result.data) || typeof result.has_more !== 'boolean') throw new Error('Invalid Stripe list response.');
    for (const item of result.data) {
      if (!item.id || seen.has(item.id)) throw new Error('Stripe pagination repeated an object; rerun the report.');
      seen.add(item.id);
      items.push(item);
    }
    if (!result.has_more) return items;
    if (!result.data.length) throw new Error('Stripe returned an incomplete page.');
    cursor = result.data.at(-1).id;
  }
  throw new Error('Stripe page limit reached; no partial report was produced.');
}

export function buildReport({ account, balance, ledger, charges, transactions, disputes = {}, startedAt, finishedAt }) {
  verifyScope(account, balance, ledger);
  const issues = [];
  const flag = (code, paymentID) => issues.push({ code, ...(paymentID ? { paymentID } : {}) });
  const chargeMap = new Map(charges.map(charge => [charge.id, charge]));
  const transactionMap = new Map(transactions.map(transaction => [transaction.id, transaction]));
  const payments = ledger.payments;
  const known = new Set(payments.map(payment => payment.chargeID));
  for (const charge of charges) {
    if (charge.livemode !== true) throw new Error('Mixed Stripe modes.');
    if (charge.paid && charge.captured && !known.has(charge.id)) {
      flag(charge.metadata?.application === 'untitled-faith' ? 'stripe_payment_missing_from_ledger' : 'unattributed_stripe_charge', charge.id);
    }
  }
  for (const p of payments) {
    for (const key of ['grossCents', 'feeCents', 'refundedCents', 'usageMicros', 'developerMicros', 'shareBps',
      'allocatedUsageMicros', 'allocatedDeveloperMicros']) integer(p[key]);
    if (p.livemode !== 1) throw new Error('Mixed ledger modes.');
    if (p.allocatedUsageMicros !== p.usageMicros || p.allocatedDeveloperMicros !== p.developerMicros) flag('allocation_ledger_mismatch', p.id);
    const c = chargeMap.get(p.chargeID);
    if (!c) { flag('ledger_payment_missing_from_stripe', p.id); continue; }
    if (c.metadata?.application !== 'untitled-faith' || c.metadata?.intent_id !== p.intentID ||
        id(c.payment_intent) !== p.id || c.currency !== 'usd' || !c.paid || !c.captured || c.status !== 'succeeded' ||
        c.amount !== p.grossCents || c.amount_refunded !== p.refundedCents) flag('charge_snapshot_mismatch', p.id);
    let disputed = false, disputeOpen = false;
    if (c.disputed) {
      const records = disputes[c.id];
      if (!Array.isArray(records) || !records.length) { flag('dispute_status_unknown', p.id); continue; }
      disputed = records.some(d => !['won', 'warning_closed'].includes(d.status));
      disputeOpen = records.some(d => !['won', 'lost', 'warning_closed'].includes(d.status));
    }
    if (Boolean(p.disputed) !== disputed || Boolean(p.disputeOpen) !== disputeOpen) flag('dispute_snapshot_mismatch', p.id);
    if (disputeOpen) flag('open_dispute', p.id);
    const b = c.balance_transaction;
    if (!b || typeof b === 'string' || !p.feeConfirmed) flag('fee_reconciliation_pending', p.id);
    if (b && typeof b !== 'string') {
      if (b.currency !== 'usd' || b.amount !== p.grossCents || b.net !== b.amount - b.fee ||
          b.fee !== p.feeCents) flag('fee_snapshot_mismatch', p.id);
      const t = transactionMap.get(b.id);
      if (!t || t.amount !== b.amount || t.fee !== b.fee || t.net !== b.net || t.currency !== b.currency || id(t.source) !== c.id) {
        flag('charge_balance_transaction_mismatch', p.id);
      }
    }
    // Recheck the selected percentage against the existing allocation policy, including refund rounding.
    const remaining = disputed ? 0 : p.grossCents - p.refundedCents;
    const net = Math.max(0, remaining - p.feeCents);
    const developer = Math.min(net, Math.floor((remaining * p.shareBps + 5000) / 10_000));
    if (p.developerMicros !== micros(developer) || p.usageMicros !== micros(net - developer)) flag('payment_split_mismatch', p.id);
  }
  const stripeUsage = sum(payments.map(p => p.usageMicros));
  const stripeDeveloper = sum(payments.map(p => p.developerMicros));
  const usageFunding = sum([stripeUsage, ledger.legacy.usageFundingMicros]);
  const developerShare = sum([stripeDeveloper, ledger.legacy.developerShareMicros]);
  const u = ledger.usage;
  for (const value of Object.values(u)) integer(value);
  const remaining = sum([usageFunding, -u.paidSpentMicros]);
  if (remaining !== sum([u.positiveUserBalancesMicros, u.negativeUserBalancesMicros, u.detachedBalanceMicros])) flag('wallet_ledger_mismatch');
  if (u.detachedBalanceMicros) flag('deleted_account_balance_requires_review');
  if (u.negativeUserBalancesMicros) flag('negative_user_balances');
  for (const [key, value] of Object.entries(ledger.operations)) {
    if (integer(value)) flag(key);
  }
  if (ledger.legacy.usageFundingMicros || ledger.legacy.developerShareMicros) flag('legacy_allocations_not_verified_with_stripe');

  const groups = new Map();
  for (const t of transactions) {
    if (t.net !== integer(t.amount) - integer(t.fee)) throw new Error('Invalid Stripe balance transaction.');
    if (t.currency !== 'usd') throw new Error('Non-USD Stripe activity; separate currency accounting required.');
    if (t.balance_type && t.balance_type !== 'payments') flag('non_payment_stripe_balance', t.id);
    const month = new Date(integer(t.created) * 1000).toISOString().slice(0, 7);
    const key = `${month}/${t.currency}/${t.type}`;
    const group = groups.get(key) ?? { month, currency: t.currency, type: t.type, count: 0, amountMicros: 0, feeMicros: 0, netMicros: 0 };
    group.count++;
    for (const field of ['amount', 'fee', 'net']) group[`${field}Micros`] = sum([group[`${field}Micros`], micros(t[field])]);
    groups.set(key, group);
  }
  const usdTransactions = transactions.filter(t => t.currency === 'usd');
  const chargeTransactions = new Set(charges.filter(c => known.has(c.id)).map(c => id(c.balance_transaction)).filter(Boolean));
  const chargeNet = micros(sum(usdTransactions.filter(t => chargeTransactions.has(t.id)).map(t => t.net)));
  const payoutTypes = new Set(['payout', 'payout_cancel', 'payout_failure']);
  const payoutNet = micros(sum(usdTransactions.filter(t => payoutTypes.has(t.type)).map(t => t.net)));
  const otherNet = micros(sum(usdTransactions.filter(t => !chargeTransactions.has(t.id) && !payoutTypes.has(t.type)).map(t => t.net)));
  const balanceTotal = key => sum((balance[key] ?? []).map(b => {
    if (b.currency !== 'usd' && b.amount) throw new Error('Non-USD Stripe balance; separate currency accounting required.');
    return b.currency === 'usd' ? micros(b.amount) : 0;
  }));
  const available = balanceTotal('available'), pending = balanceTotal('pending');
  const balanceDifference = sum([available, pending, -chargeNet, -otherNet, -payoutNet]);
  if (balanceDifference) flag('stripe_balance_changed_or_not_reconciled');
  const overhead = sum([chargeNet, otherNet, -stripeUsage, -stripeDeveloper]);
  if (overhead) flag('stripe_cash_outside_allocations_requires_review');
  return {
    schemaVersion: 1, startedAt, finishedAt, currency: 'USD', moneyUnit: 'micro-USD',
    source: { stripeAccount: account.id, stripeProject: STRIPE_PROJECT, databaseID: DATABASE_ID, livemode: true },
    status: issues.length ? 'review' : 'matched', issues,
    allocations: { grossMicros: micros(sum(payments.map(p => p.grossCents))),
      refundedMicros: micros(sum(payments.map(p => p.refundedCents))),
      confirmedFeeMicros: micros(sum(payments.filter(p => p.feeConfirmed).map(p => p.feeCents))),
      estimatedFeeMicros: micros(sum(payments.filter(p => !p.feeConfirmed).map(p => p.feeCents))),
      stripeUsageFundingMicros: stripeUsage, stripeDeveloperShareMicros: stripeDeveloper,
      totalUsageFundingMicros: usageFunding, totalDeveloperShareMicros: developerShare },
    usage: { ...u, remainingLedgerMicros: remaining }, legacy: ledger.legacy,
    stripeCash: { availableMicros: available, pendingMicros: pending, chargeNetMicros: chargeNet,
      otherActivityNetMicros: otherNet, payoutNetMicros: payoutNet,
      cashOutsideAllocationsMicros: overhead, balanceDifferenceMicros: balanceDifference },
    operations: ledger.operations, months: ledger.months,
    transactionGroups: [...groups.values()].sort((a, b) => b.month.localeCompare(a.month) || a.type.localeCompare(b.type)),
    payments,
    limitations: [
      'Developer share is cumulative allocation after refunds, before business expenses, taxes, and owner withdrawals; it is not profit or withdrawable cash.',
      'Usage reserves are already included in user balances. Negative or deleted-account balances never become developer earnings.',
      'Stripe cash and payouts combine usage and developer funds. Bank transfers, provider top-ups, and owner withdrawals are not tracked here.',
      'D1 is one consistent snapshot; Stripe reads occur across the capture interval. Rerun after pending reconciliation or concurrent activity.',
      'Monthly allocations use the UTC date of each ledger adjustment; refunds affect their adjustment month. This is not a historical balance snapshot.',
    ],
  };
}

export function renderReport(r) {
  const a = r.allocations, u = r.usage, s = r.stripeCash;
  const row = (label, value) => `| ${label} | ${usd(value)} |`;
  return [
    '# Untitled Faith money report', '', `Captured ${r.finishedAt} · LIVE · ${r.source.stripeAccount}`,
    `Check: **${r.status}** · ${r.payments.length} payment(s) · all time · USD`, '',
    '| Allocation | Amount |', '| --- | ---: |',
    row('Payments received (Stripe gross)', a.grossMicros), row('Refunded (Stripe)', a.refundedMicros),
    row('Stripe charge fees (confirmed)', a.confirmedFeeMicros), row('Stripe charge fees (estimated)', a.estimatedFeeMicros),
    row('Usage funding after fees/refunds', a.totalUsageFundingMicros),
    row('Developer share after refunds, before expenses/withdrawals', a.totalDeveloperShareMicros), '',
    '| Usage accounting | Amount |', '| --- | ---: |',
    row('Paid usage consumed', u.paidSpentMicros), row('Remaining positive user balances', u.positiveUserBalancesMicros),
    row('Reserved for in-flight usage (included above)', u.reservedMicros),
    row('Negative user balances', u.negativeUserBalancesMicros), row('Deleted-account ledger remainder', u.detachedBalanceMicros),
    row('Free usage consumed (owner-funded expense)', u.freeSpentMicros), '',
    '| Stripe cash (combined funds) | Amount |', '| --- | ---: |',
    row('Available', s.availableMicros), row('Pending', s.pendingMicros),
    row('Payouts, net cash outflow (not developer withdrawals)', -s.payoutNetMicros),
    row('Cash outside usage/developer allocations, before payouts', s.cashOutsideAllocationsMicros),
    row('Balance reconciliation difference', s.balanceDifferenceMicros), '',
    '| UTC month | Net usage funding | Net developer share | Paid usage spent | Free usage spent |',
    '| --- | ---: | ---: | ---: | ---: |',
    ...r.months.map(m => `| ${m.month} | ${usd(m.usageFundingMicros)} | ${usd(m.developerShareMicros)} | ${usd(m.paidUsageSpentMicros)} | ${usd(m.freeUsageSpentMicros)} |`), '',
    '| Stripe activity month | Currency | Type | Gross | Fees | Net |', '| --- | --- | --- | ---: | ---: | ---: |',
    ...r.transactionGroups.map(g => `| ${g.month} | ${g.currency} | ${g.type} | ${(g.amountMicros / 1_000_000).toFixed(6)} | ${(g.feeMicros / 1_000_000).toFixed(6)} | ${(g.netMicros / 1_000_000).toFixed(6)} |`), '',
    ...(r.issues.length ? ['Review items:', '', ...r.issues.map(i => `- ${i.code}${i.paymentID ? ` (${i.paymentID})` : ''}`), ''] : []),
    ...r.limitations.map(note => `- ${note}`), '',
  ].join('\n');
}
