import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk";
import { createTwilioSmsPlugin } from "./src/channel.js";
import { setTwilioSmsRuntime } from "./src/runtime.js";

const plugin = {
  id: "twilio-sms",
  name: "Twilio SMS",
  description: "Twilio SMS/MMS channel plugin for OpenClaw",
  configSchema: emptyPluginConfigSchema(),
  register(api: OpenClawPluginApi) {
    setTwilioSmsRuntime(api.runtime);
    api.registerChannel({ plugin: createTwilioSmsPlugin() });
  },
};

export default plugin;
