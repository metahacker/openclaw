/**
 * Plugin runtime singleton.
 * Stores the PluginRuntime from api.runtime (set during register()).
 */

import type { PluginRuntime } from "openclaw/plugin-sdk";

let runtime: PluginRuntime | null = null;

export function setTwilioSmsRuntime(r: PluginRuntime): void {
  runtime = r;
}

export function getTwilioSmsRuntime(): PluginRuntime {
  if (!runtime) {
    throw new Error("Twilio SMS runtime not initialized - plugin not registered");
  }
  return runtime;
}
