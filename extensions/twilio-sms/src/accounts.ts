/**
 * Account resolution: reads config from channels.twilio-sms,
 * merges per-account overrides, falls back to environment variables.
 */


import type { TwilioSmsChannelConfig, ResolvedTwilioSmsAccount } from "./types.js";

function getChannelConfig(cfg: any): TwilioSmsChannelConfig | undefined {
  return cfg?.channels?.["twilio-sms"];
}

function parseAllowFrom(raw: string | string[] | undefined): string[] {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.map((s) => s.trim()).filter(Boolean);
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

export function listAccountIds(cfg: any): string[] {
  const channelCfg = getChannelConfig(cfg);
  if (!channelCfg) return [];

  const ids = new Set<string>();

  const hasBase =
    channelCfg.accountSid ||
    channelCfg.from ||
    process.env.TWILIO_ACCOUNT_SID ||
    process.env.TWILIO_SMS_FROM;
  if (hasBase) {
    ids.add("default");
  }

  if (channelCfg.accounts) {
    for (const id of Object.keys(channelCfg.accounts)) {
      ids.add(id);
    }
  }

  return Array.from(ids);
}

export function resolveAccount(cfg: any, accountId?: string | null): ResolvedTwilioSmsAccount {
  const channelCfg = getChannelConfig(cfg) ?? {};
  const id = accountId || "default";

  const accountOverride = channelCfg.accounts?.[id] ?? {};

  const envAccountSid = process.env.TWILIO_ACCOUNT_SID ?? "";
  const envAuthToken = process.env.TWILIO_AUTH_TOKEN ?? "";
  const envFrom = process.env.TWILIO_SMS_FROM ?? "";

  const accountSid = accountOverride.accountSid ?? channelCfg.accountSid ?? envAccountSid;
  const authToken = accountOverride.authToken ?? channelCfg.authToken ?? envAuthToken;
  const from = accountOverride.from ?? channelCfg.from ?? envFrom;

  return {
    accountId: id,
    enabled: accountOverride.enabled ?? channelCfg.enabled ?? true,
    accountSid,
    authToken,
    from,
    webhookPath:
      accountOverride.webhookPath ?? channelCfg.webhookPath ?? "/webhook/twilio-sms",
    dmPolicy: accountOverride.dmPolicy ?? channelCfg.dmPolicy ?? "allowlist",
    allowFrom: parseAllowFrom(accountOverride.allowFrom ?? channelCfg.allowFrom),
    rateLimitPerMinute:
      accountOverride.rateLimitPerMinute ?? channelCfg.rateLimitPerMinute ?? 30,
    mediaMaxMb: accountOverride.mediaMaxMb ?? channelCfg.mediaMaxMb ?? 5,
    validateSignature:
      accountOverride.validateSignature ?? channelCfg.validateSignature ?? true,
    publicUrl: accountOverride.publicUrl ?? channelCfg.publicUrl ?? "",
    configured: Boolean(accountSid && authToken && from),
  };
}
