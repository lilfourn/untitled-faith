import { APIError } from './http';

// Apple names are user-editable profile data, not verified identity claims or instructions.
export function parseFirstName(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length > 100 || /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(value)) {
    throw new APIError(400, 'invalid_request');
  }
  return value.trim().normalize('NFC') || null;
}
