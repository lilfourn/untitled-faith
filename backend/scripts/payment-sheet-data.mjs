import { LIVE_ACCOUNT } from './payment-report-core.mjs';

export const SHEET_NAMES = ['Balances', 'Monthly', 'Payments', 'Stripe activity'];
export const SHEET_TITLE = 'Untitled Faith Accounting';
export const MONEY_FORMAT = '"$"#,##0.000000';
export const DATE_FORMAT = 'yyyy-mm-dd hh:mm';
const formula = value => ({ formula: value });
const dollars = value => {
  if (!Number.isSafeInteger(value)) throw new Error('Expected integer micro-USD.');
  return value / 1_000_000;
};
export function serialDate(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error('Invalid accounting timestamp.');
  return date.getTime() / 86_400_000 + 25569;
}

export function sheetData(report) {
  if (report.schemaVersion !== 1 || report.currency !== 'USD' || report.moneyUnit !== 'micro-USD' ||
      report.source?.stripeAccount !== LIVE_ACCOUNT || report.source.livemode !== true ||
      !['matched', 'review'].includes(report.status)) throw new Error('Unexpected accounting report source or schema.');
  const a = report.allocations, u = report.usage, s = report.stripeCash;
  const balances = [
    [SHEET_TITLE],
    ['Current allocations and cash. All amounts are USD.'],
    ['Updated (UTC)', serialDate(report.finishedAt)],
    ['Items to review', report.issues.length],
    ['Refresh cadence', 'Weekly', formula('=IF(NOW()-B3>8,"No successful refresh in the last 8 days","")')],
    [], ['Metric', 'Amount (USD)', 'Meaning'],
    ['Payments received', dollars(a.grossMicros), 'Stripe payments before refunds and fees.'],
    ['Refunds', dollars(a.refundedMicros), 'Money refunded to buyers.'],
    ['Confirmed Stripe charge fees', dollars(a.confirmedFeeMicros), 'Verified charge processing fees.'],
    ['Estimated Stripe charge fees', dollars(a.estimatedFeeMicros), 'Provisional fees still awaiting confirmation.'],
    ['Usage funding', dollars(a.totalUsageFundingMicros), 'Cumulative usage allocation after fees and refunds.'],
    ['Developer share', dollars(a.totalDeveloperShareMicros), 'Cumulative allocation after refunds, before expenses and withdrawals.'],
    ['Paid usage consumed', dollars(u.paidSpentMicros), 'Settled AI usage funded by buyers.'],
    ['Usage ledger remainder', formula('=B12-B14'), 'Usage funding less paid usage consumed.'],
    ['Positive user balances', dollars(u.positiveUserBalancesMicros), 'Outstanding credit held by current users.'],
    ['Negative user balances', dollars(u.negativeUserBalancesMicros), 'Refunded or disputed funding already consumed.'],
    ['Deleted-account remainder', dollars(u.detachedBalanceMicros), 'Retained accounting requiring review, never developer earnings.'],
    ['Usage reserved', dollars(u.reservedMicros), 'Already included in user balances. Do not subtract it again.'],
    ['Free usage consumed', dollars(u.freeSpentMicros), 'Owner-funded AI cost, separate from buyer-funded usage.'],
    ['Stripe available', dollars(s.availableMicros), 'Combined usage and developer cash available in Stripe.'],
    ['Stripe pending', dollars(s.pendingMicros), 'Combined cash awaiting settlement.'],
    ['Total held in Stripe', formula('=SUM(B21:B22)'), 'Available plus pending cash.'],
    ['Net bank payouts', dollars(-s.payoutNetMicros), 'Combined funds paid out; includes payout reversals.'],
    ['Cash outside allocations', dollars(s.cashOutsideAllocationsMicros), 'Retained fees or other Stripe cash activity requiring review.'],
    ['Stripe reconciliation difference', dollars(s.balanceDifferenceMicros), 'Expected to be zero when captured Stripe records reconcile.'],
    ['Usage reconciliation difference', formula('=B15-SUM(B16:B18)'), 'Expected to be zero when funding, spending, and balances reconcile.'],
    [], ['Review items', 'Payment reference'],
    ...(report.issues.length ? report.issues.map(issue => [issue.code, issue.paymentID ?? '']) : [['No outstanding review items']]),
    [], ['Sources and definitions'],
    ['Stripe account', '', `https://dashboard.stripe.com/${LIVE_ACCOUNT}`],
    ['App ledger', '', 'Untitled Faith production accounting database. No buyer identities are included.'],
    ['Stripe balance definitions', '', 'https://docs.stripe.com/payments/balances'],
    ['Monthly dates', '', 'UTC ledger adjustment dates. Refunds reduce the month in which the adjustment was recorded.'],
    ['Refresh availability', '', 'Monday at 9 AM local Mac time, or when the Mac next wakes. Requires internet and valid data-service logins.'],
    ['Accounting boundary', '', 'Bank balances, provider top-ups, taxes, other expenses, and developer withdrawals are not imported.'],
    ['Editing', '', 'These four tabs refresh automatically. Add a separate tab for your own notes or calculations.'],
  ];
  const base = (title, description, columns, rows) => [
    [title], [description], ['Updated (UTC)', serialDate(report.finishedAt)], [], [], columns, ...rows,
  ];
  return [
    { name: 'Balances', rows: balances, widths: [290, 195, 550], headerRows: [7, 29], moneyRanges: ['B8:B27'], dateRanges: ['B3'] },
    { name: 'Monthly', rows: base('Monthly allocations and usage', 'USD. Net adjustments by UTC month.',
      ['Month', 'Usage funding', 'Developer share', 'Paid usage consumed', 'Free usage consumed'],
      report.months.map(m => [m.month, dollars(m.usageFundingMicros), dollars(m.developerShareMicros),
        dollars(m.paidUsageSpentMicros), dollars(m.freeUsageSpentMicros)])),
      widths: [145, 175, 175, 190, 190], headerRows: [6], moneyColumns: [1, 2, 3, 4], dateRanges: ['B3'] },
    { name: 'Payments', rows: base('Payment allocations', 'USD. Latest verified allocation for each payment, including refunds and fee corrections.',
      ['Payment ID', 'Recorded (UTC)', 'Payment', 'Stripe fee', 'Refunded', 'Usage allocation', 'Developer share', 'Selected share', 'Fee status', 'Dispute', 'Checked (UTC)'],
      report.payments.map(p => [p.id, serialDate(p.createdAt), p.grossCents / 100, p.feeCents / 100,
        p.refundedCents / 100, dollars(p.usageMicros), dollars(p.developerMicros), p.shareBps / 10_000,
        p.feeConfirmed ? 'Confirmed' : 'Estimated', p.disputeOpen ? 'Open' : p.disputed ? 'Funding unavailable' : 'None', serialDate(p.checkedAt)])),
      widths: [320, 155, 110, 110, 110, 150, 145, 120, 120, 150, 155], headerRows: [6], moneyColumns: [2, 3, 4, 5, 6],
      dateColumns: [1, 10], percentColumns: [7], dateRanges: ['B3'] },
    { name: 'Stripe activity', rows: base('Stripe cash activity', 'USD. Gross, fees, and net changes grouped by UTC month and Stripe transaction type.',
      ['Month', 'Transaction type', 'Count', 'Gross change', 'Fees', 'Net change'],
      report.transactionGroups.map(g => [g.month, g.type, g.count, dollars(g.amountMicros), dollars(g.feeMicros), dollars(g.netMicros)])),
      widths: [145, 220, 100, 160, 150, 160], headerRows: [6], moneyColumns: [3, 4, 5], dateRanges: ['B3'] },
  ];
}

export function enteredValue(value) {
  if (value === null || value === undefined || value === '') return {};
  if (typeof value === 'object' && typeof value.formula === 'string') return { userEnteredValue: { formulaValue: value.formula } };
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Invalid numeric cell.');
    return { userEnteredValue: { numberValue: value } };
  }
  // Explicit strings keep payment identifiers or upstream text from becoming formulas.
  return { userEnteredValue: { stringValue: String(value) } };
}

export function updateRequests(data, properties) {
  return data.flatMap(sheet => {
    const target = properties.find(p => p.title === sheet.name);
    if (!target) throw new Error(`Missing managed tab: ${sheet.name}`);
    const rowCount = Math.max(target.gridProperties.rowCount, sheet.rows.length);
    const columnCount = Math.max(target.gridProperties.columnCount, sheet.widths.length);
    return [
      { updateSheetProperties: { properties: { sheetId: target.sheetId, gridProperties: { rowCount, columnCount } }, fields: 'gridProperties.rowCount,gridProperties.columnCount' } },
      { updateCells: { range: { sheetId: target.sheetId, startRowIndex: 0, endRowIndex: rowCount,
        startColumnIndex: 0, endColumnIndex: sheet.widths.length },
        rows: sheet.rows.map(row => ({ values: row.map(enteredValue) })), fields: 'userEnteredValue' } },
      ...sheet.moneyColumns?.map(column => formatColumn(target.sheetId, column, rowCount, 'NUMBER', MONEY_FORMAT)) ?? [],
      ...sheet.dateColumns?.map(column => formatColumn(target.sheetId, column, rowCount, 'DATE_TIME', DATE_FORMAT)) ?? [],
      ...sheet.percentColumns?.map(column => formatColumn(target.sheetId, column, rowCount, 'PERCENT', '0.0%')) ?? [],
    ];
  });
}

function formatColumn(sheetId, column, rowCount, type, pattern) {
  return { repeatCell: { range: { sheetId, startRowIndex: 6, endRowIndex: rowCount, startColumnIndex: column, endColumnIndex: column + 1 },
    cell: { userEnteredFormat: { numberFormat: { type, pattern } } }, fields: 'userEnteredFormat.numberFormat' } };
}
