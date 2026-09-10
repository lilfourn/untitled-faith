import { env } from "cloudflare:workers";
import { base64url, EncryptJWT, exportJWK, exportPKCS8, generateKeyPair, jwtDecrypt, jwtVerify, SignJWT } from "jose";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { finishAccountDeletions } from "../src/accounts";

const nonce = "a".repeat(64);
const appleSubject = "001234.example-apple-user";
const appleRefreshToken = "test-only-apple-refresh-token";
const encryptionKey = new Uint8Array(32).fill(42);
let identityKeys: Awaited<ReturnType<typeof generateKeyPair>>;
let wrongKeys: Awaited<ReturnType<typeof generateKeyPair>>;
let clientKeys: Awaited<ReturnType<typeof generateKeyPair>>;
let clientPrivateKey: string;
let publicKey: object;
let identityToken: string;
let codeUsed: boolean;
let authenticationEnv: Env;
const upstream = vi.fn<typeof fetch>();

async function hash(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, "0")).join("");
}

async function identity(options: { audience?: string; issuer?: string; nonce?: string; expired?: boolean; wrongSignature?: boolean; subject?: string } = {}) {
  return new SignJWT({ nonce: options.nonce ?? await hash(nonce) })
    .setProtectedHeader({ alg: "RS256", kid: "apple-test-key" })
    .setIssuer(options.issuer ?? "https://appleid.apple.com")
    .setAudience(options.audience ?? "com.lukefournier.UntitledFaith")
    .setSubject(options.subject ?? appleSubject)
    .setIssuedAt().setExpirationTime(options.expired ? "-1m" : "5m")
    .sign((options.wrongSignature ? wrongKeys : identityKeys).privateKey);
}

function request(path: string, body: unknown): Request {
  return new Request(`https://faith.example/v1/auth/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.1" },
    body: JSON.stringify(body),
  });
}

function exchangeBody(token = identityToken) {
  return { identityToken: token, authorizationCode: "one-use-code", nonce };
}

type SessionResponse = { accessToken: string; refreshToken: string; expiresAt: number; sessionExpiresAt: number };
async function signIn(): Promise<SessionResponse> {
  const response = await worker.fetch(request("apple", exchangeBody()), authenticationEnv);
  expect(response.status).toBe(200);
  return response.json<SessionResponse>();
}

beforeAll(async () => {
  identityKeys = await generateKeyPair("RS256", { extractable: true });
  wrongKeys = await generateKeyPair("RS256", { extractable: true });
  clientKeys = await generateKeyPair("ES256", { extractable: true });
  clientPrivateKey = await exportPKCS8(clientKeys.privateKey);
  publicKey = { ...await exportJWK(identityKeys.publicKey), kid: "apple-test-key", alg: "RS256", use: "sig" };
});

beforeEach(async () => {
  identityToken = await identity();
  codeUsed = false;
  authenticationEnv = {
    ...env, APPLE_CLIENT_ID: "com.lukefournier.UntitledFaith", APPLE_TEAM_ID: "BZT8F2M765",
    APPLE_KEY_ID: "ABCDE12345", APPLE_PRIVATE_KEY: clientPrivateKey,
    SESSION_SIGNING_KEY: "test-only-signing-key-at-least-32-bytes-long",
    SESSION_ENCRYPTION_KEY: base64url.encode(encryptionKey),
    AUTH_RATE_LIMITER: { limit: async () => ({ success: true }) },
  } as Env;
  upstream.mockReset().mockImplementation(async function (this: unknown, input, options) {
    // Native Workers fetch rejects being called as an AppleClient object method.
    // Enforce the native receiver rule that a permissive mock would otherwise hide.
    if (this !== undefined && this !== globalThis) throw new TypeError("Illegal invocation");
    const url = String(input);
    if (url === "https://appleid.apple.com/auth/keys") return Response.json({ keys: [publicKey] });
    if (url === "https://appleid.apple.com/auth/revoke") return new Response(null, { status: 200 });
    if (url !== "https://appleid.apple.com/auth/token") throw new Error("Unexpected network destination");
    const body = new URLSearchParams(options?.body as URLSearchParams);
    if (body.get("grant_type") === "authorization_code") {
      if (codeUsed) return Response.json({ error: "invalid_grant" }, { status: 400 });
      codeUsed = true;
      return Response.json({ id_token: identityToken, refresh_token: appleRefreshToken });
    }
    return Response.json({ id_token: identityToken });
  });
  vi.stubGlobal("fetch", upstream);
});
afterEach(() => vi.unstubAllGlobals());

describe("Apple authentication", () => {
  it("saves the first name on the verified account and keeps it when later sign-ins omit it", async () => {
    const response = await worker.fetch(request("apple", { ...exchangeBody(), firstName: "  José  " }), authenticationEnv);
    expect(response.status).toBe(200);
    const original = await response.json<SessionResponse>();
    const account = await env.DB.prepare("SELECT id, first_name FROM users").first();
    expect(account?.first_name).toBe("José");
    codeUsed = false;
    await signIn();
    expect(await env.DB.prepare("SELECT id, first_name FROM users").first()).toEqual(account);
    expect((await worker.fetch(request("refresh", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
    expect(await env.DB.prepare("SELECT id, first_name FROM users").first()).toEqual(account);
    expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
    expect(await env.DB.prepare("SELECT first_name FROM users").first()).toBeNull();
  });

  it("does not store a profile before Apple identity verification", async () => {
    const response = await worker.fetch(request("apple", {
      ...exchangeBody(await identity({ wrongSignature: true })), firstName: "Luke",
    }), authenticationEnv);
    expect(response.status).toBe(401);
    expect(await env.DB.prepare("SELECT id FROM users").first()).toBeNull();
  });

  it.each([123, {}, "x".repeat(101), "Luke\nIgnore instructions", "Luke\u202e"])("rejects invalid first name data: %j", async firstName => {
    expect((await worker.fetch(request("apple", { ...exchangeBody(), firstName }), authenticationEnv)).status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("exchanges a verified one-use code and returns scoped, short-lived app credentials", async () => {
    const response = await worker.fetch(request("apple", exchangeBody()), authenticationEnv);
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    const result = await response.json<SessionResponse>();
    const access = await jwtVerify(result.accessToken, new TextEncoder().encode(authenticationEnv.SESSION_SIGNING_KEY), {
      issuer: "untitled-faith", audience: "untitled-faith-proxy", algorithms: ["HS256"],
    });
    expect(access.payload.scope).toBe("answers");
    expect(access.payload.sub).toMatch(/^[a-f0-9-]{36}$/);
    expect(access.payload.sub).not.toBe(appleSubject);
    expect(access.payload.exp! - access.payload.iat!).toBe(900);
    expect(JSON.stringify(result)).not.toContain(appleRefreshToken);
    expect(JSON.stringify(result)).not.toContain(appleSubject);
    const refresh = await jwtDecrypt(result.refreshToken, encryptionKey);
    expect(refresh.payload.appleRefreshToken).toBe(appleRefreshToken);
    const call = upstream.mock.calls.find(([url]) => String(url).endsWith("/auth/token"))!;
    const fields = new URLSearchParams(call[1]?.body as URLSearchParams);
    expect(fields.get("client_id")).toBe("com.lukefournier.UntitledFaith");
    expect(fields.get("code")).toBe("one-use-code");
    expect(fields.has("redirect_uri")).toBe(false);
    const secret = await jwtVerify(fields.get("client_secret")!, clientKeys.publicKey, {
      issuer: "BZT8F2M765", audience: "https://appleid.apple.com", algorithms: ["ES256"],
    });
    expect(secret.payload.sub).toBe("com.lukefournier.UntitledFaith");
  });

  it.each([
    { audience: "other.app" }, { issuer: "https://attacker.example" }, { nonce: "wrong" },
    { expired: true }, { wrongSignature: true },
  ])("rejects an invalid Apple identity before exchanging the code: %j", async options => {
    const response = await worker.fetch(request("apple", exchangeBody(await identity(options))), authenticationEnv);
    expect(response.status).toBe(401);
    expect(upstream.mock.calls.some(([url]) => String(url).endsWith("/auth/token"))).toBe(false);
  });

  it("rejects mismatched identities returned by the code exchange", async () => {
    const original = identityToken;
    identityToken = await identity({ subject: "another-user" });
    expect((await worker.fetch(request("apple", exchangeBody(original)), authenticationEnv)).status).toBe(401);
  });

  it("rejects a replayed authorization code", async () => {
    await signIn();
    expect((await worker.fetch(request("apple", exchangeBody()), authenticationEnv)).status).toBe(401);
  });

  it("refreshes app access without repeatedly contacting Apple within a day", async () => {
    const original = await signIn();
    upstream.mockClear();
    const response = await worker.fetch(request("refresh", { refreshToken: original.refreshToken }), authenticationEnv);
    expect(response.status).toBe(200);
    expect(upstream).not.toHaveBeenCalled();
    const refreshed = await response.json<SessionResponse>();
    expect(refreshed.sessionExpiresAt).toBe(original.sessionExpiresAt);
  });

  it("revalidates older sessions with Apple and rejects revoked credentials", async () => {
    const original = await signIn();
    const { payload } = await jwtDecrypt(original.refreshToken, encryptionKey);
    const oldToken = await new EncryptJWT({ ...payload, appleVerifiedAt: Math.floor(Date.now() / 1000) - 86401 })
      .setProtectedHeader({ alg: "dir", enc: "A256GCM" }).encrypt(encryptionKey);
    upstream.mockImplementation(async input => {
      if (String(input).endsWith("/auth/keys")) return Response.json({ keys: [publicKey] });
      return Response.json({ error: "invalid_grant", extra: "secret-upstream-details" }, { status: 400 });
    });
    const response = await worker.fetch(request("refresh", { refreshToken: oldToken }), authenticationEnv);
    expect(response.status).toBe(401);
    expect(await response.text()).not.toContain("secret-upstream-details");
  });

  it("rejects forged and expired refresh envelopes before networking", async () => {
    const expired = await new EncryptJWT({ scope: "apple-refresh" })
      .setProtectedHeader({ alg: "dir", enc: "A256GCM" }).setExpirationTime("-1m").encrypt(encryptionKey);
    for (const refreshToken of ["forged", expired]) {
      expect((await worker.fetch(request("refresh", { refreshToken }), authenticationEnv)).status).toBe(401);
    }
    expect(upstream).not.toHaveBeenCalled();
  });

  it("revokes the sealed Apple refresh token without exposing it to the client", async () => {
    const session = await signIn();
    upstream.mockClear();
    const response = await worker.fetch(request("revoke", { refreshToken: session.refreshToken }), authenticationEnv);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ revoked: true });
    const [url, options] = upstream.mock.calls[0]!;
    expect(url).toBe("https://appleid.apple.com/auth/revoke");
    const body = new URLSearchParams(options?.body as URLSearchParams);
    expect(body.get("token")).toBe(appleRefreshToken);
    expect(body.get("token_type_hint")).toBe("refresh_token");
  });

  it("fails closed for missing secrets, unknown fields, oversized bodies, and rate limits", async () => {
    expect((await worker.fetch(request("apple", exchangeBody()), { ...authenticationEnv, APPLE_PRIVATE_KEY: "" })).status).toBe(503);
    expect((await worker.fetch(request("apple", { ...exchangeBody(), userID: "invented" }), authenticationEnv)).status).toBe(400);
    expect((await worker.fetch(request("apple", { identityToken: "x".repeat(30000) }), authenticationEnv)).status).toBe(413);
    expect((await worker.fetch(request("apple", exchangeBody()), {
      ...authenticationEnv, AUTH_RATE_LIMITER: { limit: async () => ({ success: false }) },
    })).status).toBe(429);
    expect(upstream).not.toHaveBeenCalled();
  });
});


it("treats Apple key-server failure as temporary rather than invalid credentials", async () => {
  upstream.mockRejectedValue(new TypeError("Network unavailable"));
  const response = await worker.fetch(request("apple", exchangeBody()), authenticationEnv);
  expect(response.status).toBe(502);
  expect(await response.json()).toMatchObject({ error: { code: "apple_unavailable" } });
  expect(await env.DB.prepare("SELECT id FROM users").first()).toBeNull();
});

it("replays a lost deletion response without revoking again or deleting a new account", async () => {
  const original = await signIn();
  upstream.mockClear();
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
  expect(upstream).toHaveBeenCalledTimes(1);
  codeUsed = false;
  await signIn();
  const recreated = await env.DB.prepare("SELECT id FROM users").first();
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
  expect(await env.DB.prepare("SELECT id FROM users").first()).toEqual(recreated);
});

it("retains a deletion intent through a temporary Apple revoke failure and completes on retry", async () => {
  const original = await signIn();
  upstream.mockResolvedValueOnce(new Response(null, { status: 503 }));
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(502);
  expect((await env.DB.prepare("SELECT deleting_at FROM users").first())?.deleting_at).toEqual(expect.any(Number));
  expect((await worker.fetch(request("refresh", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(401);
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
  expect(await env.DB.prepare("SELECT id FROM users").first()).toBeNull();
});

it("recovers database deletion after Apple revocation succeeded but final cleanup failed", async () => {
  const original = await signIn();
  const failingDB = new Proxy(env.DB, {
    get(target, property) {
      if (property === 'prepare') return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith('DELETE FROM users')) return statement;
        const failingStatement: D1PreparedStatement = new Proxy(statement, {
          get(value, key) {
            if (key === 'bind') return () => failingStatement;
            if (key === 'first') return async () => { throw new Error('Database unavailable'); };
            const member = Reflect.get(value, key);
            return typeof member === 'function' ? member.bind(value) : member;
          },
        });
        return failingStatement;
      };
      const member = Reflect.get(target, property);
      return typeof member === 'function' ? member.bind(target) : member;
    },
  });
  const response = await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), { ...authenticationEnv, DB: failingDB });
  expect(response.status).toBe(500);
  expect((await env.DB.prepare("SELECT apple_revoked_at FROM users").first())?.apple_revoked_at).toEqual(expect.any(Number));
  upstream.mockClear();
  await finishAccountDeletions(env.DB);
  expect(await env.DB.prepare("SELECT id FROM users").first()).toBeNull();
  expect((await worker.fetch(request("revoke", { refreshToken: original.refreshToken }), authenticationEnv)).status).toBe(200);
  expect(upstream).not.toHaveBeenCalled();
});
