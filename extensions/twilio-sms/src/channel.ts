/**
 * Twilio SMS Channel Plugin for OpenClaw.
 *
 * Webhook-based channel plugin following the Synology Chat pattern.
 * Supports DM SMS and lays groundwork for group MMS.
 */

import {
  DEFAULT_ACCOUNT_ID,
  setAccountEnabledInConfigSection,
  registerPluginHttpRoute,
  buildChannelConfigSchema,
  normalizeE164,
} from "openclaw/plugin-sdk";
import { z } from "zod";
import { listAccountIds, resolveAccount } from "./accounts.js";
import { sendSms, chunkSmsText } from "./client.js";
import { getTwilioSmsRuntime } from "./runtime.js";
import type { ResolvedTwilioSmsAccount } from "./types.js";
import { createWebhookHandler } from "./webhook-handler.js";

const CHANNEL_ID = "twilio-sms";
const TwilioSmsConfigSchema = buildChannelConfigSchema(z.object({}).passthrough());

const activeRouteUnregisters = new Map<string, () => void>();

export function createTwilioSmsPlugin() {
  return {
    id: CHANNEL_ID,

    meta: {
      id: CHANNEL_ID,
      label: "Twilio SMS",
      selectionLabel: "Twilio SMS/MMS",
      detailLabel: "Twilio SMS/MMS (Webhook)",
      docsPath: "/channels/twilio-sms",
      blurb: "Send and receive SMS/MMS messages via Twilio Programmable Messaging",
      order: 85,
    },

    capabilities: {
      chatTypes: ["direct" as const],
      media: true,
      threads: false,
      reactions: false,
      edit: false,
      unsend: false,
      reply: false,
      effects: false,
      blockStreaming: false,
    },

    reload: { configPrefixes: [`channels.${CHANNEL_ID}`] },

    configSchema: TwilioSmsConfigSchema,

    config: {
      listAccountIds: (cfg: any) => listAccountIds(cfg),

      resolveAccount: (cfg: any, accountId?: string | null) => resolveAccount(cfg, accountId),

      defaultAccountId: (_cfg: any) => DEFAULT_ACCOUNT_ID,

      setAccountEnabled: ({ cfg, accountId, enabled }: any) => {
        const channelConfig = cfg?.channels?.[CHANNEL_ID] ?? {};
        if (accountId === DEFAULT_ACCOUNT_ID) {
          return {
            ...cfg,
            channels: {
              ...cfg.channels,
              [CHANNEL_ID]: { ...channelConfig, enabled },
            },
          };
        }
        return setAccountEnabledInConfigSection({
          cfg,
          sectionKey: `channels.${CHANNEL_ID}`,
          accountId,
          enabled,
        });
      },
    },

    pairing: {
      idLabel: "phoneNumber",
      normalizeAllowEntry: (entry: string) => normalizeE164(entry.replace(/^twilio-sms:/i, "").trim()),
      notifyApproval: async ({ cfg, id }: { cfg: any; id: string }) => {
        const account = resolveAccount(cfg);
        if (!account.configured) return;
        await sendSms({
          accountSid: account.accountSid,
          authToken: account.authToken,
          from: account.from,
          to: id,
          body: "OpenClaw: your access has been approved. You can now send messages.",
        });
      },
    },

    security: {
      resolveDmPolicy: ({
        cfg,
        accountId,
        account,
      }: {
        cfg: any;
        accountId?: string | null;
        account: ResolvedTwilioSmsAccount;
      }) => {
        const resolvedAccountId = accountId ?? account.accountId ?? DEFAULT_ACCOUNT_ID;
        const channelCfg = cfg?.channels?.[CHANNEL_ID];
        const useAccountPath = Boolean(channelCfg?.accounts?.[resolvedAccountId]);
        const basePath = useAccountPath
          ? `channels.${CHANNEL_ID}.accounts.${resolvedAccountId}.`
          : `channels.${CHANNEL_ID}.`;
        return {
          policy: account.dmPolicy ?? "allowlist",
          allowFrom: account.allowFrom ?? [],
          policyPath: `${basePath}dmPolicy`,
          allowFromPath: basePath,
          approveHint: `openclaw pairing approve twilio-sms <phone>`,
          normalizeEntry: (raw: string) =>
            normalizeE164(raw.replace(/^twilio-sms:/i, "").trim()),
        };
      },
      collectWarnings: ({ account }: { account: ResolvedTwilioSmsAccount }) => {
        const warnings: string[] = [];
        if (!account.accountSid) {
          warnings.push(
            "- Twilio SMS: accountSid is not configured. Set channels.twilio-sms.accountSid or TWILIO_ACCOUNT_SID.",
          );
        }
        if (!account.authToken) {
          warnings.push(
            "- Twilio SMS: authToken is not configured. Set channels.twilio-sms.authToken or TWILIO_AUTH_TOKEN.",
          );
        }
        if (!account.from) {
          warnings.push(
            "- Twilio SMS: from number is not configured. Set channels.twilio-sms.from or TWILIO_SMS_FROM.",
          );
        }
        if (!account.validateSignature) {
          warnings.push(
            "- Twilio SMS: webhook signature validation is disabled. Enable channels.twilio-sms.validateSignature for production.",
          );
        }
        if (account.dmPolicy === "open") {
          warnings.push(
            '- Twilio SMS: dmPolicy="open" allows any phone number to message the bot. Consider "allowlist" for production.',
          );
        }
        if (account.dmPolicy === "allowlist" && account.allowFrom.length === 0) {
          warnings.push(
            '- Twilio SMS: dmPolicy="allowlist" with empty allowFrom blocks all senders.',
          );
        }
        return warnings;
      },
    },

    messaging: {
      normalizeTarget: (target: string) => {
        const trimmed = target.trim().replace(/^twilio-sms:/i, "");
        if (!trimmed) return undefined;
        return normalizeE164(trimmed) || trimmed;
      },
      targetResolver: {
        looksLikeId: (id: string) => {
          const trimmed = id?.trim();
          if (!trimmed) return false;
          return /^\+?\d{10,15}$/.test(trimmed) || /^twilio-sms:/i.test(trimmed);
        },
        hint: "<E.164 phone number>",
      },
    },

    directory: {
      self: async () => null,
      listPeers: async () => [],
      listGroups: async () => [],
    },

    outbound: {
      deliveryMode: "gateway" as const,
      textChunkLimit: 1500,
      chunker: (text: string, limit: number) => chunkSmsText(text, limit),

      sendText: async ({ to, text, accountId, account: ctxAccount }: any) => {
        const account: ResolvedTwilioSmsAccount =
          ctxAccount ?? resolveAccount({}, accountId);

        if (!account.configured) {
          throw new Error("Twilio SMS account not fully configured");
        }

        const result = await sendSms({
          accountSid: account.accountSid,
          authToken: account.authToken,
          from: account.from,
          to,
          body: text,
        });

        if (!result.ok) {
          throw new Error(`Failed to send SMS: ${result.error}`);
        }

        return {
          channel: CHANNEL_ID,
          messageId: result.messageSid ?? `sms-${Date.now()}`,
          chatId: to,
        };
      },

      sendMedia: async ({ to, text, mediaUrl, accountId, account: ctxAccount }: any) => {
        const account: ResolvedTwilioSmsAccount =
          ctxAccount ?? resolveAccount({}, accountId);

        if (!account.configured) {
          throw new Error("Twilio SMS account not fully configured");
        }

        const result = await sendSms({
          accountSid: account.accountSid,
          authToken: account.authToken,
          from: account.from,
          to,
          body: text || "",
          mediaUrls: mediaUrl ? [mediaUrl] : undefined,
        });

        if (!result.ok) {
          throw new Error(`Failed to send MMS: ${result.error}`);
        }

        return {
          channel: CHANNEL_ID,
          messageId: result.messageSid ?? `mms-${Date.now()}`,
          chatId: to,
        };
      },
    },

    gateway: {
      startAccount: async (ctx: any) => {
        const { cfg, accountId, log } = ctx;
        const account = resolveAccount(cfg, accountId);

        if (!account.enabled) {
          log?.info?.(`Twilio SMS account ${accountId} is disabled, skipping`);
          return { stop: () => {} };
        }

        if (!account.configured) {
          log?.warn?.(
            `Twilio SMS account ${accountId} not fully configured (missing accountSid, authToken, or from)`,
          );
          return { stop: () => {} };
        }

        if (account.dmPolicy === "allowlist" && account.allowFrom.length === 0) {
          log?.warn?.(
            `Twilio SMS account ${accountId} has dmPolicy=allowlist but empty allowFrom; refusing to start`,
          );
          return { stop: () => {} };
        }

        log?.info?.(
          `Starting Twilio SMS channel (account: ${accountId}, from: ${account.from}, path: ${account.webhookPath})`,
        );

        const handler = createWebhookHandler({
          account,
          deliver: async (msg) => {
            const rt = getTwilioSmsRuntime();
            const currentCfg = await rt.config.loadConfig();

            const msgCtx = {
              Body: msg.body,
              From: msg.from,
              To: account.from,
              SessionKey: msg.sessionKey,
              AccountId: account.accountId,
              OriginatingChannel: CHANNEL_ID as any,
              OriginatingTo: msg.from,
              ChatType: msg.chatType,
              SenderName: msg.senderName,
              SenderE164: msg.senderE164,
              MessageSid: msg.messageSid,
              ...(msg.mediaUrls && msg.mediaUrls.length > 0
                ? {
                    MediaUrls: msg.mediaUrls,
                    MediaTypes: msg.mediaTypes,
                    MediaUrl: msg.mediaUrls[0],
                    MediaType: msg.mediaTypes?.[0],
                  }
                : {}),
            };

            await rt.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
              ctx: msgCtx,
              cfg: currentCfg,
              dispatcherOptions: {
                deliver: async (payload: { text?: string; body?: string }) => {
                  const text = payload?.text ?? payload?.body;
                  if (text) {
                    await sendSms({
                      accountSid: account.accountSid,
                      authToken: account.authToken,
                      from: account.from,
                      to: msg.from,
                      body: text,
                    });
                  }
                },
                onReplyStart: () => {
                  log?.info?.(`Agent reply started for ${msg.from}`);
                },
              },
            });

            return null;
          },
          log,
        });

        // Deregister stale route from previous start
        const routeKey = `${accountId}:${account.webhookPath}`;
        const prevUnregister = activeRouteUnregisters.get(routeKey);
        if (prevUnregister) {
          log?.info?.(`Deregistering stale route before re-registering: ${account.webhookPath}`);
          prevUnregister();
          activeRouteUnregisters.delete(routeKey);
        }

        const unregister = registerPluginHttpRoute({
          path: account.webhookPath,
          pluginId: CHANNEL_ID,
          accountId: account.accountId,
          log: (msg: string) => log?.info?.(msg),
          handler,
        });
        activeRouteUnregisters.set(routeKey, unregister);

        log?.info?.(`Registered HTTP route: ${account.webhookPath} for Twilio SMS`);

        return {
          stop: () => {
            log?.info?.(`Stopping Twilio SMS channel (account: ${accountId})`);
            if (typeof unregister === "function") unregister();
            activeRouteUnregisters.delete(routeKey);
          },
        };
      },

      stopAccount: async (ctx: any) => {
        ctx.log?.info?.(`Twilio SMS account ${ctx.accountId} stopped`);
      },
    },

    agentPrompt: {
      messageToolHints: () => [
        "",
        "### SMS Formatting",
        "SMS is plain text only. Keep messages concise.",
        "",
        "**Limitations:**",
        "- No markdown, bold, italic, or code blocks (plain text only)",
        "- SMS segments are 160 chars (GSM-7) or 70 chars (Unicode)",
        "- Long messages are auto-split into multi-part SMS",
        "- MMS supports images/media up to 5MB, max 10 attachments",
        "",
        "**Best practices:**",
        "- Keep replies short and direct (SMS isn't chat)",
        "- Use line breaks to separate thoughts",
        "- Avoid tables, code blocks, or complex formatting",
        "- URLs are fine but will count toward character limits",
        "- Phone numbers are the sender identity (E.164 format: +12125551234)",
      ],
    },
  };
}
