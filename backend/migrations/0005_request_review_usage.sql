-- A question may use one request-review call followed by one answer call.
-- Only known accounting totals are stored; no conversation or review content.
ALTER TABLE usage_requests ADD COLUMN review_cost_micros INTEGER NOT NULL DEFAULT 0 CHECK (review_cost_micros >= 0);
ALTER TABLE usage_requests ADD COLUMN review_prompt_tokens INTEGER NOT NULL DEFAULT 0 CHECK (review_prompt_tokens >= 0);
ALTER TABLE usage_requests ADD COLUMN review_completion_tokens INTEGER NOT NULL DEFAULT 0 CHECK (review_completion_tokens >= 0);
