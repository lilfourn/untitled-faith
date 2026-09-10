export async function ownerPaymentSummary(db: D1Database) {
  const results = await db.batch<Record<string, string | number>>([
    db.prepare(`SELECT COUNT(*) AS payments, COALESCE(SUM(gross_cents), 0) * 10000 AS grossMicros,
      COALESCE(SUM(refunded_cents), 0) * 10000 AS refundedMicros,
      COALESCE(SUM(CASE WHEN fee_confirmed = 1 THEN fee_cents ELSE 0 END), 0) * 10000 AS confirmedFeeMicros,
      COALESCE(SUM(CASE WHEN fee_confirmed = 0 THEN fee_cents ELSE 0 END), 0) * 10000 AS estimatedFeeMicros,
      COALESCE(SUM(CASE WHEN fee_confirmed = 0 THEN 1 ELSE 0 END), 0) AS awaitingFees,
      COALESCE(SUM(CASE WHEN disputed = 1 THEN gross_cents - refunded_cents ELSE 0 END), 0) * 10000 AS disputedMicros,
      COALESCE(SUM(usage_micros), 0) AS usageFundingMicros,
      COALESCE(SUM(developer_micros), 0) AS developerShareMicros FROM stripe_payments`),
    db.prepare(`SELECT (SELECT COALESCE(SUM(delta_micros), 0) FROM developer_entries) AS developerShareMicros,
      (SELECT COALESCE(SUM(net_micros - developer_share_micros), 0) FROM contributions WHERE status = 'credited') AS usageFundingMicros`),
    db.prepare(`SELECT COALESCE(SUM(paid_balance_micros), 0) AS userBalanceMicros,
      COALESCE(SUM(paid_reserved_micros), 0) AS userReservedMicros FROM users`),
    db.prepare(`SELECT COUNT(*) AS pendingEvents FROM stripe_events WHERE status = 'pending'`),
    db.prepare(`SELECT COUNT(*) AS pendingCheckouts FROM checkout_intents WHERE status IN ('creating', 'open')`),
    db.prepare(`SELECT strftime('%Y-%m', created_at / 1000, 'unixepoch') AS month,
      SUM(usage_delta_micros) AS usageFundingMicros, SUM(developer_delta_micros) AS developerShareMicros
      FROM (SELECT created_at, usage_delta_micros, developer_delta_micros FROM payment_allocations
        UNION ALL SELECT created_at, delta_micros, 0 FROM wallet_entries WHERE kind IN ('contribution', 'refund')
        UNION ALL SELECT created_at, 0, delta_micros FROM developer_entries)
      GROUP BY month ORDER BY month DESC LIMIT 12`),
    db.prepare(`SELECT p.id, p.created_at AS createdAt, p.gross_cents * 10000 AS grossMicros,
      p.fee_cents * 10000 AS feeMicros, p.fee_confirmed AS feeConfirmed,
      p.refunded_cents * 10000 AS refundedMicros, p.disputed,
      p.usage_micros AS usageFundingMicros, p.developer_micros AS developerShareMicros
      FROM stripe_payments p ORDER BY p.created_at DESC LIMIT 30`),
  ]);
  return { currency: 'USD', stripe: results[0]!.results[0], legacy: results[1]!.results[0],
    users: results[2]!.results[0], operations: { pendingEvents: results[3]!.results[0]?.pendingEvents ?? 0, pendingCheckouts: results[4]!.results[0]?.pendingCheckouts ?? 0 },
    months: results[5]!.results, recentPayments: results[6]!.results };
}
