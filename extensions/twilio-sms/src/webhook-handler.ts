/**
 * Inbound webhook handler for Twilio SMS/MMS.
 * Parses form-urlencoded body, validates Twilio signature, delivers to agent.
 */

import type { IncomingMessage, ServerResponse } from "node:http";
import * as querystring from "node:querystring";
import { sendSms } from "./client.js";
import { validateTwilioSignature, authorizeUserForDm, RateLimiter } from "./security.js";
import type { ResolvedTwilioSmsAccount, TwilioInboundMessage } from "./types.js";

const rateLimiters = new Map<string, RateLimiter>();

function getRateLimiter(account: ResolvedTwilioSmsAccount): RateLimiter {
  let rl = rateLimiters.get(account.accountId);
  if (!rl) {
    rl = new RateLimiter(account.rateLimitPerMinute);
    rateLimiters.set(account.accountId, rl);
  }
  return rl;
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    const maxSize = 1_048_576;

    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxSize) {
        req.destroy();
        reject(new Error("Request body too large"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
    req.on("error", reject);
  });
}

/**
 * Parse Twilio webhook form body into structured message.
 */
function parsePayload(parsed: Record<string, string | string[]>): TwilioInboundMessage | null {
  const str = (key: string): string => {
    const v = parsed[key];
    return typeof v === "string" ? v : Array.isArray(v) ? v[0] ?? "" : "";
  };

  const messageSid = str("MessageSid");
  const from = str("From");
  const to = str("To");
  const body = str("Body");
  const accountSid = str("AccountSid");

  if (!messageSid || !from) return null;

  const numMedia = parseInt(str("NumMedia") || "0", 10);
  const mediaUrls: string[] = [];
  const mediaTypes: string[] = [];
  for (let i = 0; i < numMedia; i++) {
    const url = str(`MediaUrl${i}`);
    const type = str(`MediaContentType${i}`);
    if (url) mediaUrls.push(url);
    if (type) mediaTypes.push(type);
  }

  return {
    MessageSid: messageSid,
    AccountSid: accountSid,
    From: from,
    To: to,
    Body: body,
    NumMedia: numMedia,
    MediaUrls: mediaUrls,
    MediaTypes: mediaTypes,
    NumSegments: parseInt(str("NumSegments") || "1", 10),
  };
}

/**
 * Derive a stable session key from the message context.
 * For DMs: twilio-sms:<from_phone>
 * For group MMS: twilio-sms:group:<sorted_participants>
 */
function deriveSessionKey(msg: TwilioInboundMessage, botNumber: string): {
  sessionKey: string;
  chatType: "direct" | "group";
} {
  // Twilio doesn't natively expose group MMS participants in a single field.
  // For now, all inbound messages route as DMs from the sender.
  // Group MMS handling would require Twilio Conversations API or
  // participant tracking via the sorted-number-set pattern.
  return {
    sessionKey: `twilio-sms-${msg.From}`,
    chatType: "direct",
  };
}

function respond(res: ServerResponse, statusCode: number, twiml?: string) {
  if (twiml) {
    res.writeHead(statusCode, { "Content-Type": "text/xml" });
    res.end(twiml);
  } else {
    // Empty TwiML response (Twilio expects XML)
    res.writeHead(statusCode, { "Content-Type": "text/xml" });
    res.end("<Response></Response>");
  }
}

function respondError(res: ServerResponse, statusCode: number, message: string) {
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: message }));
}

export interface WebhookHandlerDeps {
  account: ResolvedTwilioSmsAccount;
  deliver: (msg: {
    body: string;
    from: string;
    senderName: string;
    provider: string;
    chatType: string;
    sessionKey: string;
    accountId: string;
    messageSid: string;
    mediaUrls?: string[];
    mediaTypes?: string[];
    senderE164: string;
  }) => Promise<string | null>;
  log?: {
    info: (...args: unknown[]) => void;
    warn: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

/**
 * Create an HTTP request handler for Twilio SMS webhooks.
 *
 * Flow:
 * 1. Parse form-urlencoded body
 * 2. Validate Twilio signature (if enabled)
 * 3. Check sender against allowlist
 * 4. Rate limit
 * 5. Deliver to agent
 * 6. Send reply via Twilio API (async, after returning 200 to Twilio)
 */
export function createWebhookHandler(deps: WebhookHandlerDeps) {
  const { account, deliver, log } = deps;
  const rateLimiter = getRateLimiter(account);

  return async (req: IncomingMessage, res: ServerResponse) => {
    if (req.method !== "POST") {
      respondError(res, 405, "Method not allowed");
      return;
    }

    let rawBody: string;
    try {
      rawBody = await readBody(req);
    } catch (err) {
      log?.error("Failed to read request body", err);
      respondError(res, 400, "Invalid request body");
      return;
    }

    const parsed = querystring.parse(rawBody) as Record<string, string | string[]>;

    // Signature validation
    if (account.validateSignature && account.authToken) {
      const signature = (req.headers["x-twilio-signature"] as string) || "";
      const webhookUrl =
        account.publicUrl ||
        `${req.headers["x-forwarded-proto"] || "https"}://${req.headers.host}${req.url}`;

      // querystring.parse returns string | string[], flatten for signature check
      const flatParams: Record<string, string> = {};
      for (const [k, v] of Object.entries(parsed)) {
        flatParams[k] = typeof v === "string" ? v : Array.isArray(v) ? v[0] ?? "" : "";
      }

      if (!validateTwilioSignature(account.authToken, signature, webhookUrl, flatParams)) {
        log?.warn(`Invalid Twilio signature from ${req.socket?.remoteAddress}`);
        respondError(res, 403, "Invalid signature");
        return;
      }
    }

    const payload = parsePayload(parsed);
    if (!payload) {
      respondError(res, 400, "Missing required fields");
      return;
    }

    // DM policy authorization
    const auth = authorizeUserForDm(payload.From, account.dmPolicy, account.allowFrom);
    if (!auth.allowed) {
      if (auth.reason === "disabled") {
        respond(res, 200); // silently drop
        return;
      }
      log?.warn(`Unauthorized sender: ${payload.From} (${auth.reason})`);
      respond(res, 200); // don't reveal auth failure to sender
      return;
    }

    // Rate limit
    if (!rateLimiter.check(payload.From)) {
      log?.warn(`Rate limit exceeded for: ${payload.From}`);
      respond(res, 200);
      return;
    }

    const { sessionKey, chatType } = deriveSessionKey(payload, account.from);

    const preview =
      payload.Body.length > 80 ? `${payload.Body.slice(0, 80)}...` : payload.Body;
    const mediaNote = payload.NumMedia > 0 ? ` [+${payload.NumMedia} media]` : "";
    log?.info(`SMS from ${payload.From}: ${preview}${mediaNote}`);

    // Respond 200 immediately (Twilio expects fast response)
    respond(res, 200);

    // Deliver to agent asynchronously
    try {
      await deliver({
        body: payload.Body,
        from: payload.From,
        senderName: payload.From, // phone number as name; identity links resolve the real name
        provider: "twilio-sms",
        chatType,
        sessionKey,
        accountId: account.accountId,
        messageSid: payload.MessageSid,
        mediaUrls: payload.MediaUrls.length > 0 ? payload.MediaUrls : undefined,
        mediaTypes: payload.MediaTypes.length > 0 ? payload.MediaTypes : undefined,
        senderE164: payload.From,
      });
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      log?.error(`Failed to process SMS from ${payload.From}: ${errMsg}`);
      // Send error reply
      try {
        await sendSms({
          accountSid: account.accountSid,
          authToken: account.authToken,
          from: account.from,
          to: payload.From,
          body: "Sorry, I encountered an error processing your message. Please try again.",
        });
      } catch (sendErr) {
        log?.error("Failed to send error reply", sendErr);
      }
    }
  };
}
