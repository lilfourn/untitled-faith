import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sheetData, enteredValue, updateRequests, serialDate, SHEET_NAMES } from './payment-sheet-data.mjs';
import { mostRecentWeeklyRun, verifyReadback } from './payment-sheets-sync.mjs';
import { LIVE_ACCOUNT } from './payment-report-core.mjs';

function report() {
  return {
    schemaVersion: 1, currency: 'USD', moneyUnit: 'micro-USD', source: { stripeAccount: LIVE_ACCOUNT, livemode: true },
    status: 'matched', finishedAt: '2026-09-13T22:20:00Z', issues: [],
    allocations: { grossMicros: 10000000, refundedMicros: 0, confirmedFeeMicros: 590000, estimatedFeeMicros: 0,
      totalUsageFundingMicros: 9110000, totalDeveloperShareMicros: 300000 },
    usage: { paidSpentMicros: 91, remainingLedgerMicros: 9109909, positiveUserBalancesMicros: 9109909,
      negativeUserBalancesMicros: 0, detachedBalanceMicros: 0, reservedMicros: 0, freeSpentMicros: 6000 },
    stripeCash: { availableMicros: 0, pendingMicros: 9410000, payoutNetMicros: 0,
      cashOutsideAllocationsMicros: 0, balanceDifferenceMicros: 0 },
    months: [{ month: '2026-09', usageFundingMicros: 9110000, developerShareMicros: 300000,
      paidUsageSpentMicros: 91, freeUsageSpentMicros: 6000 }],
    payments: [{ id: 'pi_example', createdAt: 1789336739000, checkedAt: 1789336739000,
      grossCents: 1000, feeCents: 59, refundedCents: 0, usageMicros: 9110000, developerMicros: 300000,
      shareBps: 300, feeConfirmed: 1, disputed: 0, disputeOpen: 0 }],
    transactionGroups: [{ month: '2026-09', type: 'charge', count: 1, amountMicros: 10000000, feeMicros: 590000, netMicros: 9410000 }],
  };
}

test('sheet values preserve micro-dollar usage and separate the payment allocations', () => {
  const data = sheetData(report());
  assert.deepEqual(data.map(sheet => sheet.name), SHEET_NAMES);
  assert.equal(data[0].rows[11][1], 9.11);
  assert.equal(data[0].rows[12][1], 0.30);
  assert.equal(data[0].rows[13][1], 0.000091);
  assert.equal(data[0].rows[14][1].formula, '=B12-B14');
  assert.equal(data[0].rows[26][1].formula, '=B15-SUM(B16:B18)');
  assert.equal(data[2].rows[6][5], 9.11);
  assert.equal(data[2].rows[6][6], 0.30);
  assert.equal(data[0].rows[4][1], 'Weekly');
});

test('refresh replaces payment snapshots, clears vanished rows, and preserves other tabs', () => {
  const metadata = [...SHEET_NAMES.map((title, i) => ({ title, sheetId: i + 1,
    gridProperties: { rowCount: 100, columnCount: 26 } })), { title: 'My notes', sheetId: 99 }];
  const data = sheetData(report());
  const first = updateRequests(data, metadata);
  const retry = updateRequests(data, metadata);
  assert.deepEqual(retry, first);
  assert.equal(first.filter(request => request.appendCells).length, 0);
  const payments = first.find(request => request.updateCells?.range.sheetId === 3).updateCells;
  assert.equal(payments.range.endRowIndex, 100);
  assert.equal(payments.rows.length, 7);
  assert.equal(payments.fields, 'userEnteredValue');
  assert.equal(JSON.stringify(first).includes('"sheetId":99'), false);
  assert.throws(() => updateRequests(data, metadata.filter(sheet => sheet.title !== 'Payments')));
});

test('untrusted strings cannot become sheet formulas', () => {
  assert.deepEqual(enteredValue('=IMPORTDATA("https://example.com")'), {
    userEnteredValue: { stringValue: '=IMPORTDATA("https://example.com")' },
  });
  assert.deepEqual(enteredValue({ formula: '=B12-B14' }), { userEnteredValue: { formulaValue: '=B12-B14' } });
  assert.throws(() => enteredValue(NaN));
  assert.throws(() => sheetData({ ...report(), currency: 'EUR' }));
});

test('weekly due time is Monday at 9 AM, including before the boundary and missed weeks', () => {
  assert.equal(mostRecentWeeklyRun(new Date(2026, 8, 14, 8, 59)).getTime(), new Date(2026, 8, 7, 9).getTime());
  assert.equal(mostRecentWeeklyRun(new Date(2026, 8, 14, 9)).getTime(), new Date(2026, 8, 14, 9).getTime());
  assert.equal(mostRecentWeeklyRun(new Date(2026, 8, 20, 12)).getTime(), new Date(2026, 8, 14, 9).getTime());
});

test('readback rejects stale, missing, or incorrect Google results', () => {
  const r = report();
  const readback = { valueRanges: [
    { values: [[serialDate(r.finishedAt)], [0]] },
    { values: [[9.11], [0.3], [0.000091], [9.109909], [9.109909]] },
    { values: [[0], [0]] },
  ] };
  verifyReadback(r, readback);
  readback.valueRanges[1].values[1][0] = 0.6;
  assert.throws(() => verifyReadback(r, readback));
  assert.throws(() => verifyReadback(r, { valueRanges: [] }));
});
