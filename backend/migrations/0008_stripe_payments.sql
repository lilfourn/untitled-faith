-- Stripe snapshots and append-only allocations are separate from legacy contribution records.
-- Test and live payments must use different Worker/D1 environments.
CREATE TABLE payment_environment (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  livemode INTEGER NOT NULL CHECK (livemode IN (0, 1))
) STRICT;
INSERT INTO payment_environment(id, livemode) VALUES (1, 1);

CREATE TABLE checkout_intents (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  idempotency_key TEXT NOT NULL,
  amount_cents INTEGER NOT NULL CHECK (amount_cents BETWEEN 100 AND 100000),
  developer_share_bps INTEGER NOT NULL CHECK (developer_share_bps BETWEEN 0 AND 300),
  estimated_fee_cents INTEGER NOT NULL CHECK (estimated_fee_cents >= 0 AND estimated_fee_cents < amount_cents),
  livemode INTEGER NOT NULL CHECK (livemode IN (0, 1)),
  session_id TEXT UNIQUE,
  checkout_url TEXT,
  status TEXT NOT NULL DEFAULT 'creating' CHECK (status IN ('creating', 'open', 'paid', 'expired')),
  created_at INTEGER NOT NULL,
  checked_at INTEGER NOT NULL,
  UNIQUE(user_id, idempotency_key)
) STRICT;
CREATE INDEX checkout_pending ON checkout_intents(status, checked_at);
CREATE TRIGGER checkout_account_available BEFORE INSERT ON checkout_intents BEGIN
  SELECT RAISE(ABORT, 'payment_mode_mismatch') WHERE NEW.livemode != (SELECT livemode FROM payment_environment WHERE id = 1);
  SELECT RAISE(ABORT, 'account_missing') WHERE NOT EXISTS
    (SELECT 1 FROM users WHERE id = NEW.user_id AND deleting_at IS NULL);
END;

CREATE TABLE stripe_payments (
  id TEXT PRIMARY KEY,
  intent_id TEXT NOT NULL UNIQUE REFERENCES checkout_intents(id),
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  charge_id TEXT NOT NULL UNIQUE,
  gross_cents INTEGER NOT NULL CHECK (gross_cents > 0),
  fee_cents INTEGER NOT NULL CHECK (fee_cents >= 0),
  fee_confirmed INTEGER NOT NULL CHECK (fee_confirmed IN (0, 1)),
  refunded_cents INTEGER NOT NULL CHECK (refunded_cents BETWEEN 0 AND gross_cents),
  disputed INTEGER NOT NULL CHECK (disputed IN (0, 1)),
  dispute_open INTEGER NOT NULL CHECK (dispute_open IN (0, 1)),
  usage_micros INTEGER NOT NULL CHECK (usage_micros >= 0),
  developer_micros INTEGER NOT NULL CHECK (developer_micros >= 0),
  revision INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  checked_at INTEGER NOT NULL
) STRICT;
CREATE INDEX stripe_payment_reconciliation ON stripe_payments(checked_at);

CREATE TABLE payment_allocations (
  id INTEGER PRIMARY KEY,
  payment_id TEXT NOT NULL REFERENCES stripe_payments(id),
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  revision INTEGER NOT NULL,
  usage_delta_micros INTEGER NOT NULL,
  developer_delta_micros INTEGER NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('payment', 'reconciliation')),
  created_at INTEGER NOT NULL,
  UNIQUE(payment_id, revision)
) STRICT;
CREATE TRIGGER allocate_stripe_payment AFTER INSERT ON stripe_payments BEGIN
  INSERT INTO payment_allocations(payment_id, user_id, revision, usage_delta_micros, developer_delta_micros, reason, created_at)
    VALUES (NEW.id, NEW.user_id, NEW.revision, NEW.usage_micros, NEW.developer_micros, 'payment', NEW.checked_at);
END;
CREATE TRIGGER reconcile_stripe_payment AFTER UPDATE OF revision ON stripe_payments
WHEN NEW.usage_micros != OLD.usage_micros OR NEW.developer_micros != OLD.developer_micros BEGIN
  INSERT INTO payment_allocations(payment_id, user_id, revision, usage_delta_micros, developer_delta_micros, reason, created_at)
    VALUES (NEW.id, NEW.user_id, NEW.revision, NEW.usage_micros - OLD.usage_micros,
      NEW.developer_micros - OLD.developer_micros, 'reconciliation', NEW.checked_at);
END;
CREATE TRIGGER apply_payment_allocation AFTER INSERT ON payment_allocations BEGIN
  UPDATE users SET paid_balance_micros = paid_balance_micros + NEW.usage_delta_micros WHERE id = NEW.user_id;
END;

-- The inbox is a durable retry queue. The body contains only verified routing identifiers, never card data.
CREATE TABLE stripe_events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  session_id TEXT,
  payment_intent_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'ignored')),
  created_at INTEGER NOT NULL,
  checked_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX stripe_events_pending ON stripe_events(status, checked_at);
