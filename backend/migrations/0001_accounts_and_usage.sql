-- Money is integer micro-USD: 1 dollar = 1,000,000 units. No chat content is stored.
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  identity_hash TEXT NOT NULL UNIQUE,
  app_account_token TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  paid_balance_micros INTEGER NOT NULL DEFAULT 0,
  paid_reserved_micros INTEGER NOT NULL DEFAULT 0 CHECK (paid_reserved_micros >= 0)
) STRICT;

CREATE TABLE free_months (
  month TEXT PRIMARY KEY,
  budget_micros INTEGER NOT NULL CHECK (budget_micros >= 0),
  spent_micros INTEGER NOT NULL DEFAULT 0 CHECK (spent_micros >= 0),
  reserved_micros INTEGER NOT NULL DEFAULT 0 CHECK (reserved_micros >= 0)
) STRICT;

CREATE TABLE usage_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  idempotency_key TEXT NOT NULL,
  month TEXT NOT NULL REFERENCES free_months(month),
  day TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  funding TEXT NOT NULL CHECK (funding IN ('free', 'paid')),
  status TEXT NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'settled', 'released', 'uncertain')),
  reserved_micros INTEGER NOT NULL CHECK (reserved_micros > 0),
  cost_micros INTEGER NOT NULL DEFAULT 0 CHECK (cost_micros >= 0),
  prompt_tokens INTEGER NOT NULL DEFAULT 0 CHECK (prompt_tokens >= 0),
  completion_tokens INTEGER NOT NULL DEFAULT 0 CHECK (completion_tokens >= 0),
  generation_id TEXT,
  free_daily_limit INTEGER NOT NULL,
  free_monthly_limit INTEGER NOT NULL,
  UNIQUE(user_id, idempotency_key)
) STRICT;
CREATE INDEX usage_user_month ON usage_requests(user_id, month, funding, status);
CREATE INDEX usage_user_day ON usage_requests(user_id, day, funding, status);
CREATE INDEX usage_pending ON usage_requests(status, updated_at);

CREATE TABLE contributions (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL CHECK (provider IN ('app_store', 'stripe_apple_pay')),
  transaction_id TEXT NOT NULL,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  gross_micros INTEGER NOT NULL CHECK (gross_micros > 0),
  fee_micros INTEGER NOT NULL CHECK (fee_micros >= 0 AND fee_micros < gross_micros),
  net_micros INTEGER NOT NULL CHECK (net_micros = gross_micros - fee_micros),
  status TEXT NOT NULL DEFAULT 'credited' CHECK (status IN ('credited', 'reversed')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(provider, transaction_id)
) STRICT;

CREATE TABLE wallet_entries (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  delta_micros INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('contribution', 'usage', 'refund')),
  reference_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX wallet_user_created ON wallet_entries(user_id, created_at);

-- All limits and balance checks run inside the same SQLite statement as reservation.
CREATE TRIGGER reserve_usage BEFORE INSERT ON usage_requests BEGIN
  SELECT RAISE(ABORT, 'account_missing') WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = NEW.user_id);
  SELECT RAISE(ABORT, 'request_already_processed') WHERE EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = NEW.user_id AND idempotency_key = NEW.idempotency_key);
  SELECT RAISE(ABORT, 'request_in_progress') WHERE EXISTS
    (SELECT 1 FROM usage_requests WHERE user_id = NEW.user_id AND status = 'reserved');
  SELECT RAISE(ABORT, 'free_allowance_exhausted') WHERE NEW.funding = 'free' AND (
    (SELECT COUNT(*) FROM usage_requests WHERE user_id = NEW.user_id AND month = NEW.month
      AND funding = 'free' AND status != 'released') >= NEW.free_monthly_limit OR
    (SELECT COUNT(*) FROM usage_requests WHERE user_id = NEW.user_id AND day = NEW.day
      AND funding = 'free' AND status != 'released') >= NEW.free_daily_limit);
  SELECT RAISE(ABORT, 'free_pool_exhausted') WHERE NEW.funding = 'free' AND NOT EXISTS
    (SELECT 1 FROM free_months WHERE month = NEW.month AND spent_micros + reserved_micros + NEW.reserved_micros <= budget_micros);
  SELECT RAISE(ABORT, 'insufficient_funding') WHERE NEW.funding = 'paid' AND NOT EXISTS
    (SELECT 1 FROM users WHERE id = NEW.user_id AND paid_balance_micros - paid_reserved_micros >= NEW.reserved_micros);
  UPDATE free_months SET reserved_micros = reserved_micros + NEW.reserved_micros
    WHERE month = NEW.month AND NEW.funding = 'free';
  UPDATE users SET paid_reserved_micros = paid_reserved_micros + NEW.reserved_micros
    WHERE id = NEW.user_id AND NEW.funding = 'paid';
END;

CREATE TRIGGER settle_usage AFTER UPDATE OF status ON usage_requests
WHEN OLD.status IN ('reserved', 'uncertain') AND NEW.status IN ('settled', 'released') BEGIN
  UPDATE free_months SET reserved_micros = reserved_micros - OLD.reserved_micros,
    spent_micros = spent_micros + NEW.cost_micros WHERE month = OLD.month AND OLD.funding = 'free';
  UPDATE users SET paid_reserved_micros = paid_reserved_micros - OLD.reserved_micros
    WHERE id = OLD.user_id AND OLD.funding = 'paid';
  INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
    SELECT 'usage:' || NEW.id, NEW.user_id, -NEW.cost_micros, 'usage', NEW.id, NEW.updated_at
    WHERE OLD.funding = 'paid' AND NEW.cost_micros > 0;
END;

CREATE TRIGGER credit_contribution AFTER INSERT ON contributions BEGIN
  INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
    VALUES ('contribution:' || NEW.id, NEW.user_id, NEW.net_micros, 'contribution', NEW.id, NEW.created_at);
END;
CREATE TRIGGER reverse_contribution AFTER UPDATE OF status ON contributions
WHEN OLD.status = 'credited' AND NEW.status = 'reversed' BEGIN
  INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
    VALUES ('refund:' || NEW.id, NEW.user_id, -NEW.net_micros, 'refund', NEW.id, NEW.updated_at);
END;
CREATE TRIGGER apply_wallet_entry AFTER INSERT ON wallet_entries BEGIN
  UPDATE users SET paid_balance_micros = paid_balance_micros + NEW.delta_micros WHERE id = NEW.user_id;
END;
