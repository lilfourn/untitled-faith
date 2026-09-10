import { APIError, isRecord } from "./http";

export const LEGACY_CONSENT_VERSION = "2026-09-09-openrouter-google";
export const CONSENT_VERSION = "2026-09-09-openrouter-fallbacks";
export const MAX_REQUEST_BYTES = 1024 * 1024;
export const MAX_CONTEXT_LENGTH = 200_000;
export const MAX_MESSAGES = 1000;
export type Message = { role: "user" | "assistant"; content: string };

export function parseAnswerRequest(value: unknown): Message[] {
  if (!isRecord(value) || Object.keys(value).some(key => !["messages", "consentVersion"].includes(key))) {
    throw new APIError(400, "invalid_request");
  }
  if (value.consentVersion !== CONSENT_VERSION && value.consentVersion !== LEGACY_CONSENT_VERSION) throw new APIError(403, "consent_required");
  if (!Array.isArray(value.messages) || value.messages.length < 1) {
    throw new APIError(400, "invalid_request");
  }
  if (value.messages.length > MAX_MESSAGES) throw new APIError(413, "context_too_large");
  const messages = value.messages.map((message): Message => {
    if (!isRecord(message) || Object.keys(message).some(key => !["role", "content"].includes(key)) ||
        (message.role !== "user" && message.role !== "assistant") ||
        typeof message.content !== "string" || !message.content.trim() || message.content.length > 8000) {
      throw new APIError(400, "invalid_request");
    }
    return { role: message.role, content: message.content };
  });
  if (messages[0]?.role !== "user" || messages.at(-1)?.role !== "user") {
    throw new APIError(400, "invalid_request");
  }
  if (messages.reduce((sum, message) => sum + message.content.length, 0) > MAX_CONTEXT_LENGTH) {
    throw new APIError(413, "context_too_large");
  }
  return messages;
}
