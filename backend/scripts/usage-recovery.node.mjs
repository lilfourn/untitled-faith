import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolutionSQL } from './usage-recovery.mjs';

const input = { request: '00000000-0000-4000-8000-000000000001', kind: 'verified', cost: 123,
  prompt: 10, completion: 20, reason: "Provider's receipt verified", operator: 'operator' };

test('resolution SQL quotes evidence as data and retains integer units', () => {
  const sql = resolutionSQL(input, 100);
  assert.match(sql, /123, 10, 20/);
  assert.match(sql, /'Provider''s receipt verified'/);
  assert.match(sql, /'operator', 100\);$/);
});

test('rejects unsafe amounts, incomplete evidence, and ambiguous write-offs', () => {
  for (const changed of [{ cost: NaN }, { cost: -1 }, { cost: 1.5 }, { cost: Number.MAX_SAFE_INTEGER + 1 },
    { reason: 'short' }, { operator: '' }, { request: "'; DELETE FROM users; --" }, { kind: 'write_off' }]) {
    assert.throws(() => resolutionSQL({ ...input, ...changed }));
  }
  assert.match(resolutionSQL({ ...input, kind: 'write_off', cost: 0, prompt: 0, completion: 0 }), /'write_off', 0, 0, 0/);
});
