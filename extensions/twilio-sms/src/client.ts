/**
 * Twilio SMS HTTP client.
 * Sends messages via the Twilio REST API (no SDK dependency).
 */

import * as https from "node:https";

const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01";

interface SendSmsOptions {
  accountSid: string;
  authToken: string;
  from: string;
  to: string;
  body: string;
  /** Optional media URLs for MMS (max 10, each ≤5MB) */
  mediaUrls?: string[];
}

interface SendSmsResult {
  ok: boolean;
  messageSid?: string;
  error?: string;
}

/**
 * Send an SMS or MMS message via the Twilio REST API.
 */
export async function sendSms(opts: SendSmsOptions): Promise<SendSmsResult> {
  const { accountSid, authToken, from, to, body, mediaUrls } = opts;

  const params = new URLSearchParams();
  params.append("From", from);
  params.append("To", to);
  params.append("Body", body);

  if (mediaUrls) {
    for (const url of mediaUrls) {
      params.append("MediaUrl", url);
    }
  }

  const postBody = params.toString();
  const url = `${TWILIO_API_BASE}/Accounts/${accountSid}/Messages.json`;
  const auth = Buffer.from(`${accountSid}:${authToken}`).toString("base64");

  return new Promise((resolve) => {
    const req = https.request(
      url,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Content-Length": Buffer.byteLength(postBody),
          Authorization: `Basic ${auth}`,
        },
        timeout: 30_000,
      },
      (res) => {
        let data = "";
        res.on("data", (chunk: Buffer) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          try {
            const json = JSON.parse(data);
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              resolve({ ok: true, messageSid: json.sid });
            } else {
              resolve({
                ok: false,
                error: json.message || `HTTP ${res.statusCode}`,
              });
            }
          } catch {
            resolve({
              ok: false,
              error: `Parse error: ${data.slice(0, 200)}`,
            });
          }
        });
      },
    );

    req.on("error", (err) => {
      resolve({ ok: false, error: err.message });
    });
    req.on("timeout", () => {
      req.destroy();
      resolve({ ok: false, error: "Request timeout" });
    });
    req.write(postBody);
    req.end();
  });
}

/**
 * Chunk text for SMS delivery.
 * SMS segments are 160 chars (GSM-7) or 70 chars (UCS-2).
 * We chunk at ~1500 chars to keep it readable as multi-part SMS.
 */
export function chunkSmsText(text: string, limit = 1500): string[] {
  if (text.length <= limit) return [text];

  const chunks: string[] = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= limit) {
      chunks.push(remaining);
      break;
    }

    // Try to break at newline, then sentence, then word boundary
    let breakAt = remaining.lastIndexOf("\n", limit);
    if (breakAt < limit * 0.5) {
      breakAt = remaining.lastIndexOf(". ", limit);
      if (breakAt > 0) breakAt += 1; // include the period
    }
    if (breakAt < limit * 0.3) {
      breakAt = remaining.lastIndexOf(" ", limit);
    }
    if (breakAt < limit * 0.2) {
      breakAt = limit;
    }

    chunks.push(remaining.slice(0, breakAt).trimEnd());
    remaining = remaining.slice(breakAt).trimStart();
  }

  return chunks;
}
