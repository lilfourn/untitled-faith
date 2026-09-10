import { jwtVerify } from "jose";
import { APIError } from "./http";

export async function authenticate(request: Request, signingKey: string): Promise<string> {
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer ") || header.length > 4096) throw new APIError(401, "unauthorized");
  try {
    const { payload } = await jwtVerify(header.slice(7), new TextEncoder().encode(signingKey), {
      algorithms: ["HS256"],
      issuer: "untitled-faith",
      audience: "untitled-faith-proxy",
      requiredClaims: ["sub", "exp", "iat"],
      maxTokenAge: "15m",
      clockTolerance: 5,
    });
    if (!payload.sub || payload.sub.length > 128 || payload.scope !== "answers" ||
        typeof payload.exp !== "number" || typeof payload.iat !== "number" ||
        payload.exp - payload.iat > 900) throw new Error("Invalid session");
    return payload.sub;
  } catch {
    throw new APIError(401, "unauthorized");
  }
}
