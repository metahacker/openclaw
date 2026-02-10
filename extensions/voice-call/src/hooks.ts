/**
 * Voice Call Hooks — extension points for customizing call behavior.
 *
 * Hooks are optional callbacks that, when provided, let extensions add
 * custom audio (greetings, presence sounds), transform TTS text, or react
 * to call lifecycle events — without modifying the core voice-call plugin.
 *
 * All hooks are optional. When absent, the plugin behaves identically to
 * its default (no hooks) implementation.
 */

// ---------------------------------------------------------------------------
// Stream Audio Context — passed to hooks that can send raw audio
// ---------------------------------------------------------------------------

export interface StreamAudioContext {
  /** Internal call ID */
  callId: string;
  /** Twilio stream SID */
  streamSid: string;
  /**
   * Send raw mu-law 8kHz mono audio to the caller.
   * The buffer must already be encoded as mu-law.
   */
  sendAudio: (muLawAudio: Buffer) => void;
  /** Clear any queued/playing audio (barge-in). */
  clearAudio: () => void;
}

// ---------------------------------------------------------------------------
// Hook Definitions
// ---------------------------------------------------------------------------

export interface VoiceCallHooks {
  /**
   * Called when a media stream connects and is ready for audio.
   * Use this to play greeting sounds, tones, or an initial TTS message
   * before the default `speakInitialMessage` runs.
   *
   * Return `{ skipDefaultGreeting: true }` to prevent the built-in
   * initial message from playing.
   */
  onStreamReady?: (ctx: StreamAudioContext) => Promise<{ skipDefaultGreeting?: boolean } | void>;

  /**
   * Called when the agent starts processing a user utterance
   * (after debounce fires, before Claude is called).
   * Use this to start presence/filler sounds.
   */
  onProcessingStart?: (ctx: StreamAudioContext) => void;

  /**
   * Called when the agent finishes processing (response ready or error).
   * Use this to stop presence/filler sounds.
   */
  onProcessingEnd?: (ctx: StreamAudioContext) => void;

  /**
   * Transform text just before it is sent to the TTS engine.
   * Useful for converting markdown action markers to provider-specific
   * tags (e.g., ElevenLabs v3 audio tags).
   *
   * Return the transformed text, or `undefined` to use the original
   * text unchanged.
   */
  transformTtsText?: (text: string) => string | undefined;

  /**
   * Called when a call disconnects.
   * Use this to clean up any per-call resources (timers, sound loops, etc.).
   */
  onCallEnd?: (callId: string) => void;
}
