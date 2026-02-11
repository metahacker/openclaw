/**
 * Persistent Call Agent — boots one AgentSession per call, reuses for all utterances.
 *
 * Instead of runEmbeddedPiAgent() per utterance (full cold boot each time),
 * this creates the session once on stream_ready and calls session.prompt()
 * for each utterance with streaming via subscribeEmbeddedPiSession.
 *
 * Boot: call connects → stream_ready → CallAgent.boot() (parallel with chimes)
 * Utterance: transcript arrives → CallAgent.prompt(text, onChunk) → streaming TTS
 * End: call disconnects → CallAgent.dispose()
 */

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { VoiceCallConfig } from "./config.js";
import { loadCoreAgentDeps, type CoreConfig } from "./core-bridge.js";

// Lazy-loaded core modules (from extensionAPI.js bundle)
let coreModules: any = null;

async function loadCoreModules(): Promise<any> {
  if (coreModules) return coreModules;

  // Find the OpenClaw root (same logic as core-bridge)
  let root = process.env.OPENCLAW_ROOT?.trim();
  if (!root) {
    // Walk up from process.argv[1] to find openclaw package
    let dir = path.dirname(process.argv[1] || process.cwd());
    while (dir !== path.dirname(dir)) {
      const pkgPath = path.join(dir, "package.json");
      try {
        if (fs.existsSync(pkgPath)) {
          const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
          if (pkg.name === "openclaw") {
            root = dir;
            break;
          }
        }
      } catch {}
      dir = path.dirname(dir);
    }
  }
  if (!root) throw new Error("Cannot find OpenClaw root for call-agent");

  const apiPath = path.join(root, "dist", "extensionAPI.js");
  coreModules = await import(pathToFileURL(apiPath).href);
  return coreModules;
}

type SessionEntry = { sessionId: string; updatedAt: number };

export type CallAgentResult = {
  text: string | null;
  error?: string;
};

/**
 * Persistent agent for a single phone call.
 * Boot once, prompt many times, dispose on hangup.
 */
export class CallAgent {
  private voiceConfig: VoiceCallConfig;
  private coreConfig: CoreConfig;
  private callId: string;
  private from: string;

  // Resolved on boot
  private session: any = null;
  private sessionManager: any = null;
  private sessionLock: any = null;
  private core: any = null;
  private deps: any = null;

  private booted = false;
  private bootPromise: Promise<void> | null = null;
  private bootError: string | null = null;

  constructor(voiceConfig: VoiceCallConfig, coreConfig: CoreConfig, callId: string, from: string) {
    this.voiceConfig = voiceConfig;
    this.coreConfig = coreConfig;
    this.callId = callId;
    this.from = from;
  }

  boot(): Promise<void> {
    if (this.bootPromise) return this.bootPromise;
    this.bootPromise = this._boot();
    return this.bootPromise;
  }

  get isReady(): boolean {
    return this.booted && !this.bootError;
  }

  get error(): string | null {
    return this.bootError;
  }

  private async _boot(): Promise<void> {
    const t0 = Date.now();
    try {
      // Load both core-bridge deps (for path resolution) and full core modules
      const [deps, core] = await Promise.all([loadCoreAgentDeps(), loadCoreModules()]);
      this.deps = deps;
      this.core = core;
      const cfg = this.coreConfig;
      const agentId = "main";

      // 1. Resolve paths
      const storePath = deps.resolveStorePath(cfg.session?.store, { agentId });
      const agentDir = deps.resolveAgentDir(cfg, agentId);
      const workspaceDir = deps.resolveAgentWorkspaceDir(cfg, agentId);
      await deps.ensureAgentWorkspace({ dir: workspaceDir });

      // 2. Resolve session (keyed by phone)
      const normalizedPhone = this.from.replace(/\D/g, "");
      const sessionKey = `voice:${normalizedPhone}`;
      const sessionStore = deps.loadSessionStore(storePath);
      let entry = sessionStore[sessionKey] as SessionEntry | undefined;
      if (!entry) {
        entry = { sessionId: crypto.randomUUID(), updatedAt: Date.now() };
        sessionStore[sessionKey] = entry;
        await deps.saveSessionStore(storePath, sessionStore);
      }
      const sessionId = entry.sessionId;
      const sessionFile = deps.resolveSessionFilePath(sessionId, entry, { agentId });

      // 3. Resolve model
      const modelRef =
        this.voiceConfig.responseModel || `${deps.DEFAULT_PROVIDER}/${deps.DEFAULT_MODEL}`;
      const slashIdx = modelRef.indexOf("/");
      const provider = slashIdx === -1 ? deps.DEFAULT_PROVIDER : modelRef.slice(0, slashIdx);
      const modelId = slashIdx === -1 ? modelRef : modelRef.slice(slashIdx + 1);

      // 4. Get Model object from registry
      const { model, authStorage, modelRegistry } = core.resolveModel(
        provider,
        modelId,
        agentDir,
        cfg,
      );
      if (!model) {
        throw new Error(`Model not found: ${provider}/${modelId}`);
      }

      const thinkLevel = deps.resolveThinkingDefault({ cfg, provider, model: modelId });

      // 5. Build voice system prompt
      const identity = deps.resolveAgentIdentity(cfg, agentId);
      const agentName = identity?.name?.trim() || "assistant";
      const basePrompt =
        this.voiceConfig.responseSystemPrompt ??
        `You are ${agentName}, a helpful voice assistant on a phone call. Keep responses brief and conversational (1-2 sentences max). Be natural and friendly. The caller's phone number is ${this.from}. You have access to tools - use them when helpful.`;

      // 6. Acquire session lock
      this.sessionLock = await core.acquireSessionWriteLock({ sessionFile });

      // 7. Open session manager
      this.sessionManager = core.SessionManager.open(sessionFile);

      // 8. Create persistent agent session
      const { session } = await core.createAgentSession({
        cwd: workspaceDir,
        agentDir,
        authStorage,
        modelRegistry,
        model,
        thinkingLevel: core.mapThinkingLevel(thinkLevel),
        sessionManager: this.sessionManager,
      });

      if (!session) {
        throw new Error("Failed to create agent session");
      }

      // 9. Apply system prompt override
      const systemPromptOverride = core.createSystemPromptOverride(basePrompt);
      core.applySystemPromptOverrideToSession(session, systemPromptOverride());

      // 10. Limit history
      const messages = session.messages || [];
      if (messages.length > 0) {
        const limited = core.limitHistoryTurns(messages, 20);
        if (limited.length > 0) {
          session.agent.replaceMessages(limited);
        }
      }

      this.session = session;
      this.booted = true;
      console.log(
        `[voice-call] CallAgent booted for ${this.from} in ${Date.now() - t0}ms ` +
          `(model: ${provider}/${modelId}, session: ${sessionId})`,
      );
    } catch (err) {
      this.bootError = err instanceof Error ? err.message : String(err);
      console.error(`[voice-call] CallAgent boot failed:`, err);
    }
  }

  /**
   * Send a message and stream the response.
   * onChunk fires per sentence as the LLM generates.
   */
  async prompt(
    userMessage: string,
    onChunk?: (text: string) => void | Promise<void>,
  ): Promise<CallAgentResult> {
    if (this.bootPromise && !this.booted) {
      await this.bootPromise;
    }

    if (this.bootError || !this.session || !this.core) {
      return { text: null, error: this.bootError || "Agent not booted" };
    }

    const session = this.session;
    const core = this.core;
    const allChunks: string[] = [];

    try {
      // Subscribe to streaming events BEFORE sending prompt
      const subscription = core.subscribeEmbeddedPiSession({
        session,
        runId: `voice:${this.callId}:${Date.now()}`,
        verboseLevel: "off",
        onBlockReply: async (payload: { text?: string }) => {
          if (!payload.text) return;
          const trimmed = payload.text.trim();
          if (!trimmed) return;
          allChunks.push(trimmed);
          console.log(
            `[voice-call] CallAgent chunk (${trimmed.length} chars): "${trimmed.slice(0, 80)}${trimmed.length > 80 ? "..." : ""}"`,
          );
          if (onChunk) await onChunk(trimmed);
        },
        blockReplyBreak: "text_end",
        blockReplyChunking: {
          minChars: 20,
          maxChars: 200,
          breakPreference: "sentence",
          flushOnParagraph: true,
        },
      });

      // Send prompt to the SAME persistent session
      await session.prompt(userMessage);

      // Unsubscribe
      subscription.unsubscribe();

      if (allChunks.length === 0) {
        // Fallback: check last assistant message
        const msgs = session.messages || [];
        const lastAssistant = [...msgs].reverse().find((m: any) => m.role === "assistant");
        if (lastAssistant) {
          const text = core.extractAssistantText?.(lastAssistant);
          if (text) return { text };
        }
        return { text: null, error: "No response generated" };
      }

      return { text: allChunks.join(" ") };
    } catch (err) {
      console.error(`[voice-call] CallAgent prompt failed:`, err);
      return {
        text: allChunks.length > 0 ? allChunks.join(" ") : null,
        error: String(err),
      };
    }
  }

  dispose(): void {
    try {
      this.session?.dispose?.();
      this.session = null;
      this.sessionLock?.release?.();
      this.sessionLock = null;
      this.sessionManager?.flush?.();
      this.sessionManager = null;
    } catch (err) {
      console.warn(`[voice-call] CallAgent dispose error:`, err);
    }
    console.log(`[voice-call] CallAgent disposed for ${this.from}`);
  }

  getFrom(): string {
    return this.from;
  }
}

// ---------------------------------------------------------------------------
// Per-call agent cache
// ---------------------------------------------------------------------------

const callAgents = new Map<string, CallAgent>();

export function bootCallAgent(
  voiceConfig: VoiceCallConfig,
  coreConfig: CoreConfig,
  callId: string,
  from: string,
): CallAgent {
  let agent = callAgents.get(callId);
  if (agent) return agent;

  agent = new CallAgent(voiceConfig, coreConfig, callId, from);
  callAgents.set(callId, agent);

  agent.boot().catch((err) => {
    console.error(`[voice-call] CallAgent boot error for ${callId}:`, err);
  });

  return agent;
}

export function getCallAgent(callId: string): CallAgent | undefined {
  return callAgents.get(callId);
}

export function teardownCallAgent(callId: string): void {
  const agent = callAgents.get(callId);
  if (agent) {
    agent.dispose();
    callAgents.delete(callId);
  }
}
