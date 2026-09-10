-- Users may spend their entire monthly free allowance on any day.
-- Retain the legacy free_daily_limit column for old Workers and ledger history,
-- but never consult it when reserving a request. All other atomic checks remain.
DROP TRIGGER reserve_usage;

CREATE TRIGGER reserve_usage BEFORE INSERT ON usage_requests BEGIN
  SELECT RAISE(ABORT, 'account_missing') WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.user_id);
  SELECT RAISE(ABORT, 'request_already_processed') WHERE EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = NEW.user_id AND idempotency_key = NEW.idempotency_key);
  SELECT RAISE(ABORT, 'request_in_progress') WHERE EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = NEW.user_id AND status = 'reserved');
  SELECT RAISE(ABORT, 'free_allowance_exhausted') WHERE NEW.funding = 'free' AND (
    (SELECT COUNT(*) FROM usage_requests WHERE user_id = NEW.user_id AND month = NEW.month
      AND funding = 'free' AND status != 'released') >= NEW.free_monthly_limit);
  SELECT RAISE(ABORT, 'free_pool_exhausted') WHERE NEW.funding = 'free' AND NOT EXISTS
    (SELECT 1 FROM free_months WHERE month = NEW.month AND spent_micros + reserved_micros + NEW.reserved_micros <= budget_micros);
  SELECT RAISE(ABORT, 'insufficient_funding') WHERE NEW.funding = 'paid' AND NOT EXISTS
    (SELECT 1 FROM users WHERE id = NEW.user_id AND paid_balance_micros - paid_reserved_micros >= NEW.reserved_micros);
  UPDATE free_months SET reserved_micros = reserved_micros + NEW.reserved_micros
    WHERE month = NEW.month AND NEW.funding = 'free';
  UPDATE users SET paid_reserved_micros = paid_reserved_micros + NEW.reserved_micros
    WHERE id = NEW.user_id AND NEW.funding = 'paid';
END;
