import { base64url, EncryptJWT, jwtDecrypt, SignJWT } from "jose";
import { AppleClient } from "./apple-client";
import { APIError, isRecord, jsonResponse, readJSON } from "./http";
import { accountForIdentity, beginAccountDeletion, cancelAccountDeletion, deleteAccountData, requireAccount } from "./accounts";
import { parseFirstName } from "./account-profile";

const DAY = 24 * 60 * 60;
const SESSION_LIFETIME = 30 * DAY;
const REFRESH_AUDIENCE = "untitled-faith-refresh";

type RefreshState = {
  subject: string;
  appleSubject: string;
  appleRefreshToken: string;
  appleVerifiedAt: number;
  expiresAt: number;
};

export async function handleAppleAuth(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") throw new APIError(405, "method_not_allowed");
  if (request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    throw new APIError(415, "invalid_request");
  }
  const route = new URL(request.url).pathname;
  if (!["/v1/auth/apple", "/v1/auth/refresh", "/v1/auth/revoke"].includes(route)) {
    throw new APIError(404, "not_found");
  }
  const encryptionKey = configurationKey(env);
  const client = new AppleClient({
    clientID: env.APPLE_CLIENT_ID, teamID: env.APPLE_TEAM_ID,
    keyID: env.APPLE_KEY_ID, privateKey: env.APPLE_PRIVATE_KEY,
  });
  const rateKey = await sha256(request.headers.get("CF-Connecting-IP") ?? "unknown");
  if (!(await env.AUTH_RATE_LIMITER.limit({ key: `auth:${rateKey}` })).success) throw new APIError(429, "rate_limited");
  const input = await readJSON(request.body, 24 * 1024);
  if (!isRecord(input)) throw new APIError(400, "invalid_request");

  if (route === "/v1/auth/apple") {
    exactKeys(input, ["identityToken", "authorizationCode", "nonce", "firstName"]);
    const firstName = parseFirstName(input.firstName);
    const identityToken = stringField(input.identityToken, 8192);
    const code = stringField(input.authorizationCode, 4096);
    const nonce = stringField(input.nonce, 64);
    if (!/^[a-f0-9]{64}$/.test(nonce)) throw new APIError(400, "invalid_request");
    const expectedNonce = await sha256(nonce);
    const identity = await client.verifyIdentity(identityToken, expectedNonce);
    if (identity.c_hash !== undefined) {
      const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(code));
      if (identity.c_hash !== base64url.encode(new Uint8Array(digest).slice(0, 16))) {
        throw new APIError(401, "invalid_apple_credential");
      }
    }
    // Apple's one-use code exchange prevents an intercepted identity token from being replayed alone.
    const tokens = await client.exchangeCode(code, request.signal);
    const exchangedIdentity = await client.verifyIdentity(tokens.identityToken, expectedNonce);
    if (exchangedIdentity.sub !== identity.sub) throw new APIError(401, "invalid_apple_credential");
    const now = Math.floor(Date.now() / 1000);
    const account = await accountForIdentity(env.DB, await sha256(`${env.APPLE_CLIENT_ID}:${identity.sub}`), firstName);
    return issueSession({
      subject: account.id,
      appleSubject: identity.sub,
      appleRefreshToken: tokens.refreshToken,
      appleVerifiedAt: now,
      expiresAt: now + SESSION_LIFETIME,
    }, env.SESSION_SIGNING_KEY, encryptionKey);
  }

  exactKeys(input, ["refreshToken"]);
  const state = await openRefreshToken(stringField(input.refreshToken, 16384), encryptionKey);
  if (route === "/v1/auth/revoke") {
    await requireAccount(env.DB, state.subject, true);
    await beginAccountDeletion(env.DB, state.subject);
    try { await client.revoke(state.appleRefreshToken, request.signal); }
    catch (error) { await cancelAccountDeletion(env.DB, state.subject); throw error; }
    await deleteAccountData(env.DB, state.subject);
    return jsonResponse({ revoked: true });
  }
  await requireAccount(env.DB, state.subject);

  // Apple recommends checking its refresh token no more than once a day.
  // The app also checks Apple's on-device credential state when restoring its session.
  if (Math.floor(Date.now() / 1000) - state.appleVerifiedAt >= DAY) {
    const tokens = await client.refresh(state.appleRefreshToken, request.signal);
    const identity = await client.verifyIdentity(tokens.identityToken);
    if (identity.sub !== state.appleSubject) throw new APIError(401, "invalid_apple_credential");
    state.appleRefreshToken = tokens.refreshToken;
    state.appleVerifiedAt = Math.floor(Date.now() / 1000);
  }
  return issueSession(state, env.SESSION_SIGNING_KEY, encryptionKey);
}

function configurationKey(env: Env): Uint8Array {
  if (!env.APPLE_CLIENT_ID || !/^[A-Z0-9]{10}$/.test(env.APPLE_TEAM_ID ?? "") ||
      !/^[A-Z0-9]{10}$/.test(env.APPLE_KEY_ID ?? "") || !env.APPLE_PRIVATE_KEY?.trim() ||
      !env.SESSION_SIGNING_KEY || env.SESSION_SIGNING_KEY.length < 32 ||
      !/^[A-Za-z0-9_-]{43}$/.test(env.SESSION_ENCRYPTION_KEY ?? "")) {
    throw new APIError(503, "auth_not_configured");
  }
  const key = base64url.decode(env.SESSION_ENCRYPTION_KEY);
  if (key.length !== 32) throw new APIError(503, "auth_not_configured");
  return key;
}

async function issueSession(state: RefreshState, signingKey: string, encryptionKey: Uint8Array): Promise<Response> {
  const expiresAt = Math.min(Math.floor(Date.now() / 1000) + 900, state.expiresAt);
  const accessToken = await new SignJWT({ scope: "answers" })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer("untitled-faith").setAudience("untitled-faith-proxy")
    .setSubject(state.subject).setIssuedAt().setExpirationTime(expiresAt)
    .sign(new TextEncoder().encode(signingKey));
  // Apple's refresh token is sealed for the server. The client stores only this opaque envelope in Keychain.
  const refreshToken = await new EncryptJWT({
    scope: "apple-refresh", appleSubject: state.appleSubject,
    appleRefreshToken: state.appleRefreshToken, appleVerifiedAt: state.appleVerifiedAt,
  })
    .setProtectedHeader({ alg: "dir", enc: "A256GCM", typ: "JWT" })
    .setIssuer("untitled-faith").setAudience(REFRESH_AUDIENCE)
    .setSubject(state.subject).setIssuedAt().setExpirationTime(state.expiresAt)
    .encrypt(encryptionKey);
  return jsonResponse({ accessToken, refreshToken, expiresAt, sessionExpiresAt: state.expiresAt });
}

async function openRefreshToken(token: string, key: Uint8Array): Promise<RefreshState> {
  try {
    const { payload } = await jwtDecrypt(token, key, {
      keyManagementAlgorithms: ["dir"], contentEncryptionAlgorithms: ["A256GCM"],
      issuer: "untitled-faith", audience: REFRESH_AUDIENCE,
      requiredClaims: ["sub", "iat", "exp"],
    });
    const now = Math.floor(Date.now() / 1000);
    if (payload.scope !== "apple-refresh" || typeof payload.sub !== "string" ||
        !/^[a-f0-9-]{36}$/.test(payload.sub) || typeof payload.appleSubject !== "string" ||
        !payload.appleSubject || payload.appleSubject.length > 255 ||
        typeof payload.appleRefreshToken !== "string" || !payload.appleRefreshToken || payload.appleRefreshToken.length > 8192 ||
        typeof payload.appleVerifiedAt !== "number" || !Number.isFinite(payload.appleVerifiedAt) ||
        payload.appleVerifiedAt > now + 5 || typeof payload.exp !== "number" || payload.exp > now + SESSION_LIFETIME + 5) {
      throw new Error("Invalid session");
    }
    return { subject: payload.sub, appleSubject: payload.appleSubject,
      appleRefreshToken: payload.appleRefreshToken, appleVerifiedAt: payload.appleVerifiedAt, expiresAt: payload.exp };
  } catch {
    throw new APIError(401, "invalid_session");
  }
}

function stringField(value: unknown, maximum: number): string {
  if (typeof value !== "string" || !value || value.length > maximum) throw new APIError(400, "invalid_request");
  return value;
}

function exactKeys(value: Record<string, unknown>, keys: string[]): void {
  if (Object.keys(value).some(key => !keys.includes(key))) throw new APIError(400, "invalid_request");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}
