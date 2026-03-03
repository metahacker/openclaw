/**
 * Type definitions for the Twilio SMS channel plugin.
 */

/** Raw channel config from openclaw.json channels.twilio-sms */
export interface TwilioSmsChannelConfig {
  enabled?: boolean;
  accountSid?: string;
  authToken?: string;
  from?: string;
  webhookPath?: string;
  dmPolicy?: "open" | "allowlist" | "pairing" | "disabled";
  allowFrom?: string | string[];
  rateLimitPerMinute?: number;
  /** Max MMS attachment size in MB (Twilio limit: 5MB) */
  mediaMaxMb?: number;
  /** Validate inbound webhook signatures (recommended for production) */
  validateSignature?: boolean;
  /** Public URL for signature validation (required if behind proxy) */
  publicUrl?: string;
  accounts?: Record<string, TwilioSmsAccountRaw>;
}

/** Raw per-account config (overrides base config) */
export interface TwilioSmsAccountRaw {
  enabled?: boolean;
  accountSid?: string;
  authToken?: string;
  from?: string;
  webhookPath?: string;
  dmPolicy?: "open" | "allowlist" | "pairing" | "disabled";
  allowFrom?: string | string[];
  rateLimitPerMinute?: number;
  mediaMaxMb?: number;
  validateSignature?: boolean;
  publicUrl?: string;
}

/** Fully resolved account config with defaults applied */
export interface ResolvedTwilioSmsAccount {
  accountId: string;
  enabled: boolean;
  accountSid: string;
  authToken: string;
  from: string;
  webhookPath: string;
  dmPolicy: "open" | "allowlist" | "pairing" | "disabled";
  allowFrom: string[];
  rateLimitPerMinute: number;
  mediaMaxMb: number;
  validateSignature: boolean;
  publicUrl: string;
  configured: boolean;
}

/** Parsed inbound Twilio webhook payload */
export interface TwilioInboundMessage {
  MessageSid: string;
  AccountSid: string;
  From: string;
  To: string;
  Body: string;
  NumMedia: number;
  /** Media URLs (MediaUrl0, MediaUrl1, ...) */
  MediaUrls: string[];
  /** Media content types (MediaContentType0, ...) */
  MediaTypes: string[];
  /** For MMS group: all participants (From + additional recipients) */
  NumSegments?: number;
}
