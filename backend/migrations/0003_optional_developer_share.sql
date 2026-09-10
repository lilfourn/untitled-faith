-- Optional developer thanks is part of the original contribution, never added to its total.
ALTER TABLE contributions ADD COLUMN developer_share_bps INTEGER NOT NULL DEFAULT 0
  CHECK (developer_share_bps >= 0 AND developer_share_bps <= 300);
ALTER TABLE contributions ADD COLUMN developer_share_micros INTEGER NOT NULL DEFAULT 0
  CHECK (developer_share_micros >= 0 AND developer_share_micros <= net_micros
    AND developer_share_micros = ((gross_micros * developer_share_bps + 50000000) / 100000000) * 10000);

CREATE TABLE developer_entries (
  id TEXT PRIMARY KEY,
  contribution_id TEXT NOT NULL REFERENCES contributions(id),
  delta_micros INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('thanks', 'refund')),
  created_at INTEGER NOT NULL
) STRICT;

DROP TRIGGER credit_contribution;
CREATE TRIGGER credit_contribution AFTER INSERT ON contributions BEGIN
  INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
    VALUES ('contribution:' || NEW.id, NEW.user_id, NEW.net_micros - NEW.developer_share_micros, 'contribution', NEW.id, NEW.created_at);
  INSERT INTO developer_entries(id, contribution_id, delta_micros, kind, created_at)
    SELECT 'thanks:' || NEW.id, NEW.id, NEW.developer_share_micros, 'thanks', NEW.created_at
    WHERE NEW.developer_share_micros > 0;
END;

DROP TRIGGER reverse_contribution;
CREATE TRIGGER reverse_contribution AFTER UPDATE OF status ON contributions
WHEN OLD.status = 'credited' AND NEW.status = 'reversed' BEGIN
  INSERT INTO wallet_entries(id, user_id, delta_micros, kind, reference_id, created_at)
    VALUES ('refund:' || NEW.id, NEW.user_id, -(NEW.net_micros - NEW.developer_share_micros), 'refund', NEW.id, NEW.updated_at);
  INSERT INTO developer_entries(id, contribution_id, delta_micros, kind, created_at)
    SELECT 'refund:' || NEW.id, NEW.id, -NEW.developer_share_micros, 'refund', NEW.updated_at
    WHERE NEW.developer_share_micros > 0;
END;
