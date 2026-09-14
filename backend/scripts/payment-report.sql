-- One read-only statement gives internally consistent totals, without buyer identities.
WITH movements AS (
  SELECT created_at, usage_delta_micros AS funding, developer_delta_micros AS developer,
    0 AS paid_spend, 0 AS free_spend FROM payment_allocations
  UNION ALL
  SELECT created_at, CASE WHEN kind != 'usage' THEN delta_micros ELSE 0 END, 0,
    CASE WHEN kind = 'usage' THEN -delta_micros ELSE 0 END, 0 FROM wallet_entries
  UNION ALL
  SELECT created_at, 0, delta_micros, 0, 0 FROM developer_entries
  UNION ALL
  SELECT updated_at, 0, 0, 0, cost_micros FROM usage_requests
    WHERE funding = 'free' AND status IN ('settled', 'released')
), months AS (
  SELECT strftime('%Y-%m', created_at / 1000, 'unixepoch') AS month,
    SUM(funding) AS usageFundingMicros, SUM(developer) AS developerShareMicros,
    SUM(paid_spend) AS paidUsageSpentMicros, SUM(free_spend) AS freeUsageSpentMicros
    FROM movements GROUP BY month ORDER BY month DESC
)
SELECT json_object(
  'livemode', (SELECT livemode FROM payment_environment WHERE id = 1),
  'payments', (SELECT json_group_array(json_object(
    'id', p.id, 'chargeID', p.charge_id, 'intentID', p.intent_id,
    'grossCents', p.gross_cents, 'feeCents', p.fee_cents, 'feeConfirmed', p.fee_confirmed,
    'refundedCents', p.refunded_cents, 'disputed', p.disputed, 'disputeOpen', p.dispute_open,
    'usageMicros', p.usage_micros, 'developerMicros', p.developer_micros,
    'shareBps', i.developer_share_bps, 'livemode', i.livemode,
    'createdAt', p.created_at, 'checkedAt', p.checked_at,
    'allocatedUsageMicros', (SELECT COALESCE(SUM(usage_delta_micros), 0) FROM payment_allocations WHERE payment_id = p.id),
    'allocatedDeveloperMicros', (SELECT COALESCE(SUM(developer_delta_micros), 0) FROM payment_allocations WHERE payment_id = p.id)
  )) FROM stripe_payments p LEFT JOIN checkout_intents i ON i.id = p.intent_id),
  'usage', json_object(
    'paidSpentMicros', (SELECT COALESCE(-SUM(delta_micros), 0) FROM wallet_entries WHERE kind = 'usage'),
    'freeSpentMicros', (SELECT COALESCE(SUM(cost_micros), 0) FROM usage_requests WHERE funding = 'free' AND status IN ('settled', 'released')),
    'positiveUserBalancesMicros', (SELECT COALESCE(SUM(MAX(0, paid_balance_micros)), 0) FROM users),
    'negativeUserBalancesMicros', (SELECT COALESCE(SUM(MIN(0, paid_balance_micros)), 0) FROM users),
    'reservedMicros', (SELECT COALESCE(SUM(paid_reserved_micros), 0) FROM users),
    'detachedBalanceMicros', (SELECT COALESCE(SUM(delta), 0) FROM (
      SELECT usage_delta_micros AS delta FROM payment_allocations WHERE user_id IS NULL
      UNION ALL SELECT delta_micros FROM wallet_entries WHERE user_id IS NULL))
  ),
  'legacy', json_object(
    'usageFundingMicros', (SELECT COALESCE(SUM(delta_micros), 0) FROM wallet_entries WHERE kind != 'usage'),
    'developerShareMicros', (SELECT COALESCE(SUM(delta_micros), 0) FROM developer_entries)
  ),
  'operations', json_object(
    'pendingEvents', (SELECT COUNT(*) FROM stripe_events WHERE status = 'pending'),
    'pendingCheckouts', (SELECT COUNT(*) FROM checkout_intents WHERE status IN ('creating', 'open')),
    'unsettledUsage', (SELECT COUNT(*) FROM usage_requests WHERE status IN ('reserved', 'uncertain'))
  ),
  'months', (SELECT json_group_array(json_object('month', month,
    'usageFundingMicros', usageFundingMicros, 'developerShareMicros', developerShareMicros,
    'paidUsageSpentMicros', paidUsageSpentMicros, 'freeUsageSpentMicros', freeUsageSpentMicros)) FROM months)
) AS snapshot;
