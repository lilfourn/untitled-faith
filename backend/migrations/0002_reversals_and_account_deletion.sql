ALTER TABLE users ADD COLUMN deleting_at INTEGER;

CREATE TABLE contribution_reversals (
  provider TEXT NOT NULL,
  transaction_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(provider, transaction_id)
) STRICT;
CREATE TRIGGER reject_reversed_contribution BEFORE INSERT ON contributions BEGIN
  SELECT RAISE(ABORT, 'contribution_reversed') WHERE EXISTS
    (SELECT 1 FROM contribution_reversals WHERE provider = NEW.provider AND transaction_id = NEW.transaction_id);
  SELECT RAISE(ABORT, 'account_missing') WHERE NOT EXISTS
    (SELECT 1 FROM users WHERE id = NEW.user_id AND deleting_at IS NULL);
END;
CREATE TRIGGER reject_deleting_account BEFORE INSERT ON usage_requests BEGIN
  SELECT RAISE(ABORT, 'account_missing') WHERE NOT EXISTS
    (SELECT 1 FROM users WHERE id = NEW.user_id AND deleting_at IS NULL);
END;
