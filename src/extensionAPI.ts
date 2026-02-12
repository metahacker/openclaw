export { resolveAgentDir, resolveAgentWorkspaceDir } from "./agents/agent-scope.ts";

export { DEFAULT_MODEL, DEFAULT_PROVIDER } from "./agents/defaults.ts";
export { resolveAgentIdentity } from "./agents/identity.ts";
export { resolveThinkingDefault } from "./agents/model-selection.ts";
export { runEmbeddedPiAgent } from "./agents/pi-embedded.ts";
export { resolveAgentTimeoutMs } from "./agents/timeout.ts";
export { ensureAgentWorkspace } from "./agents/workspace.ts";
export {
  resolveStorePath,
  loadSessionStore,
  saveSessionStore,
  resolveSessionFilePath,
} from "./config/sessions.ts";

// Agent session primitives (for persistent per-call agents)
export { createAgentSession, SessionManager } from "@mariozechner/pi-coding-agent";
export { subscribeEmbeddedPiSession } from "./agents/pi-embedded-subscribe.ts";
export { acquireSessionWriteLock } from "./agents/session-write-lock.ts";
export { extractAssistantText } from "./agents/pi-embedded-utils.ts";
export { resolveModel } from "./agents/pi-embedded-runner/model.ts";
export { mapThinkingLevel } from "./agents/pi-embedded-runner/utils.ts";
export { limitHistoryTurns } from "./agents/pi-embedded-runner/history.ts";
export {
  applySystemPromptOverrideToSession,
  createSystemPromptOverride,
} from "./agents/pi-embedded-runner/system-prompt.ts";
export { getApiKeyForModel } from "./agents/model-auth.ts";
