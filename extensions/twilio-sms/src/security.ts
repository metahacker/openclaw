/**
 * Security module: Twilio signature validation, rate limiting, input sanitization.
 */

import * as crypto from "node:crypto";

/**
 * Validate Twilio webhook signature (X-Twilio-Signature).
 * See: https://www.twilio.com/docs/usage/security#validating-requests
 *
 * @param authToken - Twilio auth token
 * @param signature - Value of X-Twilio-Signature header
 * @param url - Full URL Twilio sent the request to
 * @param params - POST body parameters as key-value pairs
 */
export function validateTwilioSignature(
  authToken: string,
  signature: string,
  url: string,
  params: Record<string, string>,
): boolean {
  if (!authToken || !signature || !url) return false;

  // Build the data string: URL + sorted params concatenated as key+value
  const sortedKeys = Object.keys(params).sort();
  let data = url;
  for (const key of sortedKeys) {
    data += key + (params[key] ?? "");
  }

  const expected = crypto
    .createHmac("sha1", authToken)
    .update(data, "utf-8")
    .digest("base64");

  // Constant-time comparison
  if (expected.length !== signature.length) return false;
  const a = Buffer.from(expected, "utf-8");
  const b = Buffer.from(signature, "utf-8");
  return crypto.timingSafeEqual(a, b);
}

export type DmAuthorizationResult =
  | { allowed: true }
  | { allowed: false; reason: "disabled" | "allowlist-empty" | "not-allowlisted" };

export function authorizeUserForDm(
  phoneNumber: string,
  dmPolicy: "open" | "allowlist" | "pairing" | "disabled",
  allowFrom: string[],
): DmAuthorizationResult {
  if (dmPolicy === "disabled") {
    return { allowed: false, reason: "disabled" };
  }
  if (dmPolicy === "open" || dmPolicy === "pairing") {
    return { allowed: true };
  }
  // allowlist
  if (allowFrom.length === 0) {
    return { allowed: false, reason: "allowlist-empty" };
  }
  // Normalize both sides for comparison
  const normalized = phoneNumber.replace(/[^\d+]/g, "");
  const match = allowFrom.some((entry) => {
    if (entry === "*") return true;
    const normalizedEntry = entry.replace(/[^\d+]/g, "");
    return normalized === normalizedEntry || normalized.endsWith(normalizedEntry.replace(/^\+/, ""));
  });
  if (!match) {
    return { allowed: false, reason: "not-allowlisted" };
  }
  return { allowed: true };
}

/**
 * Sliding window rate limiter per phone number.
 */
export class RateLimiter {
  private requests: Map<string, number[]> = new Map();
  private limit: number;
  private windowMs: number;
  private lastCleanup = 0;
  private cleanupIntervalMs: number;

  constructor(limit = 30, windowSeconds = 60) {
    this.limit = limit;
    this.windowMs = windowSeconds * 1000;
    this.cleanupIntervalMs = this.windowMs * 5;
  }

  check(userId: string): boolean {
    const now = Date.now();
    const windowStart = now - this.windowMs;

    if (now - this.lastCleanup > this.cleanupIntervalMs) {
      this.cleanup(windowStart);
      this.lastCleanup = now;
    }

    let timestamps = this.requests.get(userId);
    if (timestamps) {
      timestamps = timestamps.filter((ts) => ts > windowStart);
    } else {
      timestamps = [];
    }

    if (timestamps.length >= this.limit) {
      this.requests.set(userId, timestamps);
      return false;
    }

    timestamps.push(now);
    this.requests.set(userId, timestamps);
    return true;
  }

  private cleanup(windowStart: number): void {
    for (const [userId, timestamps] of this.requests) {
      const active = timestamps.filter((ts) => ts > windowStart);
      if (active.length === 0) {
        this.requests.delete(userId);
      } else {
        this.requests.set(userId, active);
      }
    }
  }
}
