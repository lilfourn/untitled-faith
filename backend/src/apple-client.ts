import { createRemoteJWKSet, customFetch, importPKCS8, jwtVerify, SignJWT, type JWTPayload } from "jose";
import { APIError, isRecord, readJSON } from "./http";

export type AppleConfiguration = {
  clientID: string;
  teamID: string;
  keyID: string;
  privateKey: string;
};

export class AppleClient {
  private readonly keys;

  constructor(private readonly configuration: AppleConfiguration,
              private readonly fetcher: typeof fetch = (input, init) => fetch(input, init)) {
    // One resolver per auth request: share keys within this request, not in-flight I/O across requests.
    this.keys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"), {
      [customFetch]: fetcher,
      timeoutDuration: 10000,
    });
  }

  async verifyIdentity(token: string, expectedNonce?: string): Promise<JWTPayload & { sub: string }> {
    try {
      const { payload } = await jwtVerify(token, this.keys, {
        algorithms: ["RS256"],
        issuer: "https://appleid.apple.com",
        audience: this.configuration.clientID,
        requiredClaims: ["sub", "iat", "exp", ...(expectedNonce ? ["nonce"] : [])],
        clockTolerance: 5,
        ...(expectedNonce ? { maxTokenAge: "10m" } : {}),
      });
      if (!payload.sub || payload.sub.length > 255 ||
          (expectedNonce && payload.nonce !== expectedNonce)) throw new Error("Invalid identity");
      return { ...payload, sub: payload.sub };
    } catch {
      throw new APIError(401, "invalid_apple_credential");
    }
  }

  async exchangeCode(code: string, signal: AbortSignal): Promise<{ identityToken: string; refreshToken: string }> {
    const value = await this.tokenRequest({ grant_type: "authorization_code", code }, signal);
    if (!isRecord(value) || !validToken(value.id_token) || !validToken(value.refresh_token)) {
      throw new APIError(502, "apple_unavailable");
    }
    return { identityToken: value.id_token, refreshToken: value.refresh_token };
  }

  async refresh(refreshToken: string, signal: AbortSignal): Promise<{ identityToken: string; refreshToken: string }> {
    const value = await this.tokenRequest({ grant_type: "refresh_token", refresh_token: refreshToken }, signal);
    if (!isRecord(value) || !validToken(value.id_token) ||
        (value.refresh_token !== undefined && !validToken(value.refresh_token))) {
      throw new APIError(502, "apple_unavailable");
    }
    return { identityToken: value.id_token, refreshToken: typeof value.refresh_token === "string" ? value.refresh_token : refreshToken };
  }

  async revoke(refreshToken: string, signal: AbortSignal): Promise<void> {
    const response = await this.request("revoke", { token: refreshToken, token_type_hint: "refresh_token" }, signal);
    await response.body?.cancel();
    if (!response.ok) throw new APIError(502, "apple_unavailable");
  }

  private async tokenRequest(fields: Record<string, string>, signal: AbortSignal): Promise<unknown> {
    const response = await this.request("token", fields, signal);
    let value: unknown;
    try {
      value = await readJSON(response.body, 32 * 1024);
    } catch {
      throw new APIError(502, "apple_unavailable");
    }
    if (!response.ok) {
      if (isRecord(value) && value.error === "invalid_grant") throw new APIError(401, "invalid_apple_credential");
      // Never expose Apple's response, credentials, or client-secret configuration.
      throw new APIError(502, "apple_unavailable");
    }
    return value;
  }

  private async request(endpoint: "token" | "revoke", fields: Record<string, string>, signal: AbortSignal): Promise<Response> {
    const clientSecret = await this.clientSecret();
    try {
      return await this.fetcher(`https://appleid.apple.com/auth/${endpoint}`, {
        method: "POST",
        redirect: "manual",
        signal: AbortSignal.any([signal, AbortSignal.timeout(10000)]),
        headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
        body: new URLSearchParams({ ...fields, client_id: this.configuration.clientID, client_secret: clientSecret }),
      });
    } catch {
      throw new APIError(502, "apple_unavailable");
    }
  }

  private async clientSecret(): Promise<string> {
    try {
      const key = await importPKCS8(this.configuration.privateKey.replaceAll("\\n", "\n"), "ES256");
      return await new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: this.configuration.keyID })
        .setIssuer(this.configuration.teamID)
        .setSubject(this.configuration.clientID)
        .setAudience("https://appleid.apple.com")
        .setIssuedAt()
        .setExpirationTime("5m")
        .sign(key);
    } catch {
      throw new APIError(503, "auth_not_configured");
    }
  }
}

function validToken(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 8192;
}
