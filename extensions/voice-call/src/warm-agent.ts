/**
 * Warm Agent Context — boots the full OpenClaw agent once per call,
 * reuses it for every utterance. No re-initialization overhead per turn.
 *
 * Boot sequence:
 *   call connects → stream_ready → boot() runs in parallel with healing tones
 *   → agent context cached → ready for first utterance + personalized greeting
 *
 * Usage:
 *   const agent = new WarmAgentContext(voiceConfig, coreConfig, callId, from);
 *   await agent.boot();                    // call this on stream_ready
 *   const greeting = agent.getGreeting();  // personalized based on caller
 *   const result = await agent.respond(userMessage, transcript);
 */

import crypto from "node:crypto";
import type { VoiceCallConfig } from "./config.js";
import { loadCoreAgentDeps, type CoreConfig } from "./core-bridge.js";

type SessionEntry = {
  sessionId: string;
  updatedAt: number;
};

type AgentDeps = Awaited<ReturnType<typeof loadCoreAgentDeps>>;

export type WarmResponseResult = {
  text: string | null;
  error?: string;
};

/**
 * Pre-resolved agent context, cached per call.
 */
export class WarmAgentContext {
  private voiceConfig: VoiceCallConfig;
  private coreConfig: CoreConfig;
  private callId: string;
  private from: string;

  // Pre-resolved on boot()
  private deps: AgentDeps | null = null;
  private sessionId: string | null = null;
  private sessionKey: string | null = null;
  private sessionFile: string | null = null;
  private workspaceDir: string | null = null;
  private agentDir: string | null = null;
  private provider: string | null = null;
  private model: string | null = null;
  private thinkLevel: string | null = null;
  private agentName: string = "assistant";
  private basePrompt: string = "";
  private timeoutMs: number = 30_000;

  private booted = false;
  private bootPromise: Promise<void> | null = null;
  private bootError: string | null = null;

  constructor(voiceConfig: VoiceCallConfig, coreConfig: CoreConfig, callId: string, from: string) {
    this.voiceConfig = voiceConfig;
    this.coreConfig = coreConfig;
    this.callId = callId;
    this.from = from;
  }

  /**
   * Boot the agent context. Call this on stream_ready (parallel with chimes).
   * Safe to call multiple times — subsequent calls return the same promise.
   */
  boot(): Promise<void> {
    if (this.bootPromise) return this.bootPromise;
    this.bootPromise = this._boot();
    return this.bootPromise;
  }

  /** Whether the agent is booted and ready for respond() calls. */
  get isReady(): boolean {
    return this.booted && !this.bootError;
  }

  /** Boot error message, if any. */
  get error(): string | null {
    return this.bootError;
  }

  private async _boot(): Promise<void> {
    const t0 = Date.now();
    try {
      // 1. Load core deps (cached globally after first import)
      this.deps = await loadCoreAgentDeps();
      const deps = this.deps;
      const cfg = this.coreConfig;

      // 2. Resolve paths (deterministic, fast)
      const agentId = "main";
      const storePath = deps.resolveStorePath(cfg.session?.store, { agentId });
      this.agentDir = deps.resolveAgentDir(cfg, agentId);
      this.workspaceDir = deps.resolveAgentWorkspaceDir(cfg, agentId);

      // 3. Ensure workspace
      await deps.ensureAgentWorkspace({ dir: this.workspaceDir });

      // 4. Load or create session (keyed by phone number for continuity)
      const normalizedPhone = this.from.replace(/\D/g, "");
      this.sessionKey = `voice:${normalizedPhone}`;
      const sessionStore = deps.loadSessionStore(storePath);
      let entry = sessionStore[this.sessionKey] as SessionEntry | undefined;
      if (!entry) {
        entry = { sessionId: crypto.randomUUID(), updatedAt: Date.now() };
        sessionStore[this.sessionKey] = entry;
        await deps.saveSessionStore(storePath, sessionStore);
      }
      this.sessionId = entry.sessionId;
      this.sessionFile = deps.resolveSessionFilePath(this.sessionId, entry, { agentId });

      // 5. Resolve model
      const modelRef =
        this.voiceConfig.responseModel || `${deps.DEFAULT_PROVIDER}/${deps.DEFAULT_MODEL}`;
      const slashIdx = modelRef.indexOf("/");
      this.provider = slashIdx === -1 ? deps.DEFAULT_PROVIDER : modelRef.slice(0, slashIdx);
      this.model = slashIdx === -1 ? modelRef : modelRef.slice(slashIdx + 1);
      this.thinkLevel = deps.resolveThinkingDefault({
        cfg,
        provider: this.provider,
        model: this.model,
      });

      // 6. Resolve identity + base prompt
      const identity = deps.resolveAgentIdentity(cfg, agentId);
      this.agentName = identity?.name?.trim() || "assistant";
      this.basePrompt =
        this.voiceConfig.responseSystemPrompt ??
        `You are ${this.agentName}, a helpful voice assistant on a phone call. Keep responses brief and conversational (1-2 sentences max). Be natural and friendly. The caller's phone number is ${this.from}. You have access to tools - use them when helpful.`;

      // 7. Resolve timeout
      this.timeoutMs = this.voiceConfig.responseTimeoutMs ?? deps.resolveAgentTimeoutMs({ cfg });

      this.booted = true;
      console.log(`[voice-call] Warm agent booted for ${this.from} in ${Date.now() - t0}ms`);
    } catch (err) {
      this.bootError = err instanceof Error ? err.message : String(err);
      console.error(`[voice-call] Warm agent boot failed:`, err);
    }
  }

  /**
   * Send a message to the warm agent and get a response.
   * Waits for boot() if still in progress.
   */
  async respond(
    userMessage: string,
    transcript: Array<{ speaker: "user" | "bot"; text: string }>,
  ): Promise<WarmResponseResult> {
    // Wait for boot if still running
    if (this.bootPromise && !this.booted) {
      await this.bootPromise;
    }

    if (this.bootError || !this.deps) {
      return { text: null, error: this.bootError || "Agent not booted" };
    }

    // Build system prompt with current transcript
    let extraSystemPrompt = this.basePrompt;
    if (transcript.length > 0) {
      const history = transcript
        .map((e) => `${e.speaker === "bot" ? "You" : "Caller"}: ${e.text}`)
        .join("\n");
      extraSystemPrompt = `${this.basePrompt}\n\nConversation so far:\n${history}`;
    }

    const runId = `voice:${this.callId}:${Date.now()}`;

    try {
      const result = await this.deps.runEmbeddedPiAgent({
        sessionId: this.sessionId!,
        sessionKey: this.sessionKey!,
        messageProvider: "voice",
        sessionFile: this.sessionFile!,
        workspaceDir: this.workspaceDir!,
        config: this.coreConfig,
        prompt: userMessage,
        provider: this.provider!,
        model: this.model!,
        thinkLevel: this.thinkLevel!,
        verboseLevel: "off",
        timeoutMs: this.timeoutMs,
        runId,
        lane: "voice",
        extraSystemPrompt,
        agentDir: this.agentDir!,
      });

      const texts = (result.payloads ?? [])
        .filter((p) => p.text && !p.isError)
        .map((p) => p.text?.trim())
        .filter(Boolean);

      const text = texts.join(" ") || null;

      if (!text && result.meta?.aborted) {
        return { text: null, error: "Response generation was aborted" };
      }

      return { text };
    } catch (err) {
      console.error(`[voice-call] Warm agent respond failed:`, err);
      return { text: null, error: String(err) };
    }
  }

  /**
   * Get the caller's phone number (for greeting personalization).
   */
  getFrom(): string {
    return this.from;
  }

  /**
   * Get the resolved agent name.
   */
  getAgentName(): string {
    return this.agentName;
  }
}

// ---------------------------------------------------------------------------
// Per-call agent cache
// ---------------------------------------------------------------------------

const warmAgents = new Map<string, WarmAgentContext>();

/**
 * Boot a warm agent for a call. Call on stream_ready.
 * Returns the context immediately; boot happens async.
 */
export function bootWarmAgent(
  voiceConfig: VoiceCallConfig,
  coreConfig: CoreConfig,
  callId: string,
  from: string,
): WarmAgentContext {
  let agent = warmAgents.get(callId);
  if (agent) return agent;

  agent = new WarmAgentContext(voiceConfig, coreConfig, callId, from);
  warmAgents.set(callId, agent);

  // Fire boot — don't await, let it run parallel with chimes
  agent.boot().catch((err) => {
    console.error(`[voice-call] Warm agent boot error for ${callId}:`, err);
  });

  return agent;
}

/**
 * Get a warm agent for a call (must have been booted first).
 */
export function getWarmAgent(callId: string): WarmAgentContext | undefined {
  return warmAgents.get(callId);
}

/**
 * Tear down a warm agent when call ends.
 */
export function teardownWarmAgent(callId: string): void {
  warmAgents.delete(callId);
  console.log(`[voice-call] Warm agent torn down for ${callId}`);
}
