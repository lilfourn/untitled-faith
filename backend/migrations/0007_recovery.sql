-- Recovery metadata only. No prompts, answers, Apple tokens, or names.
ALTER TABLE users ADD COLUMN apple_revoked_at INTEGER;
ALTER TABLE usage_requests ADD COLUMN inference_stage TEXT NOT NULL DEFAULT 'unknown'
  CHECK (inference_stage IN ('unknown', 'reserved', 'review', 'answer'));
ALTER TABLE usage_requests ADD COLUMN reconciliation_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE usage_requests ADD COLUMN reconciliation_error TEXT;
ALTER TABLE usage_requests ADD COLUMN needs_review_at INTEGER;

CREATE TABLE usage_resolutions (
  request_id TEXT PRIMARY KEY REFERENCES usage_requests(id),
  kind TEXT NOT NULL CHECK (kind IN ('verified', 'write_off')),
  provider_cost_micros INTEGER NOT NULL CHECK (provider_cost_micros >= 0),
  prompt_tokens INTEGER NOT NULL CHECK (prompt_tokens >= 0),
  completion_tokens INTEGER NOT NULL CHECK (completion_tokens >= 0),
  reason TEXT NOT NULL CHECK (length(reason) BETWEEN 10 AND 500),
  operator TEXT NOT NULL CHECK (length(operator) BETWEEN 1 AND 100),
  created_at INTEGER NOT NULL,
  CHECK (kind != 'write_off' OR (provider_cost_micros = 0 AND prompt_tokens = 0 AND completion_tokens = 0))
) STRICT;

-- The audit insertion and financial settlement are one atomic statement. A
-- repeated or racing resolution cannot change already-settled accounting.
CREATE TRIGGER validate_usage_resolution BEFORE INSERT ON usage_resolutions BEGIN
  SELECT RAISE(ABORT, 'request_not_uncertain') WHERE NOT EXISTS
    (SELECT 1 FROM usage_requests WHERE id = NEW.request_id AND status = 'uncertain');
  SELECT RAISE(ABORT, 'resolution_overflow') WHERE EXISTS
    (SELECT 1 FROM usage_requests WHERE id = NEW.request_id AND
      (NEW.provider_cost_micros > 9007199254740991 - review_cost_micros OR
       NEW.prompt_tokens > 9007199254740991 - review_prompt_tokens OR
       NEW.completion_tokens > 9007199254740991 - review_completion_tokens));
END;
CREATE TRIGGER apply_usage_resolution AFTER INSERT ON usage_resolutions BEGIN
  UPDATE usage_requests SET status = 'settled',
    cost_micros = NEW.provider_cost_micros + review_cost_micros,
    prompt_tokens = NEW.prompt_tokens + review_prompt_tokens,
    completion_tokens = NEW.completion_tokens + review_completion_tokens,
    updated_at = NEW.created_at, needs_review_at = NULL, reconciliation_error = NULL
    WHERE id = NEW.request_id AND status = 'uncertain';
END;
