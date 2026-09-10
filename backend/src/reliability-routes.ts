import { authenticate } from './auth';
import { requireAccount } from './accounts';
import { APIError, jsonResponse } from './http';

/** Read-only operational and retry metadata. Never returns conversation text. */
export async function handleReliability(request: Request, env: Env): Promise<Response | undefined> {
  const path = new URL(request.url).pathname;
  if (path !== '/v1/readiness' && !path.startsWith('/v1/answers/status/')) return;
  if (request.method !== 'GET') throw new APIError(405, 'method_not_allowed');
  const userID = await authenticate(request, env.SESSION_SIGNING_KEY);
  await requireAccount(env.DB, userID);
  if (!(await env.ANSWERS_RATE_LIMITER.limit({ key: `status:${userID}` })).success) throw new APIError(429, 'rate_limited');
  if (path === '/v1/readiness') {
    if (!env.OPENROUTER_API_KEY?.trim() || !env.APPLE_PRIVATE_KEY?.trim() ||
        !env.SESSION_ENCRYPTION_KEY?.trim() || !env.APPLE_CLIENT_ID || !env.APPLE_TEAM_ID || !env.APPLE_KEY_ID) {
      throw new APIError(503, 'not_ready');
    }
    try {
      await env.DB.batch([
        env.DB.prepare('SELECT inference_stage, needs_review_at FROM usage_requests LIMIT 0'),
        env.DB.prepare('SELECT apple_revoked_at FROM users LIMIT 0'),
        env.DB.prepare('SELECT request_id FROM usage_resolutions LIMIT 0'),
      ]);
    } catch { throw new APIError(503, 'not_ready'); }
    return jsonResponse({ status: 'ready', recoverySchema: 7 });
  }
  const key = path.slice('/v1/answers/status/'.length);
  if (!/^[a-zA-Z0-9_-]{16,128}$/.test(key)) throw new APIError(400, 'invalid_request');
  const row = await env.DB.prepare('SELECT status FROM usage_requests WHERE user_id = ? AND idempotency_key = ?')
    .bind(userID, key).first<{ status: string }>();
  return jsonResponse({ status: row?.status ?? 'not_found' });
}
