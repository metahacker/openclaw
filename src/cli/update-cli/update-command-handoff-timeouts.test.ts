import { afterEach, expect, it, vi } from "vitest";
import type { GatewayServiceState } from "../../daemon/service-types.js";
import { startManagedServiceUpdateHandoff } from "../../infra/update-managed-service-handoff.js";
import { handoffUpdateFromGateway } from "./update-command-handoff.js";

vi.mock("../../daemon/gateway-entrypoint.js", () => ({
  resolveGatewayInstallEntrypoint: vi.fn(async () => "/opt/openclaw/dist/index.js"),
}));
vi.mock("../../infra/supervisor-markers.js", () => ({
  detectRespawnSupervisor: vi.fn(() => "systemd"),
}));
vi.mock("../../infra/update-managed-service-handoff.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../infra/update-managed-service-handoff.js")>()),
  startManagedServiceUpdateHandoff: vi.fn(async () => ({
    status: "joined",
    command: "openclaw update",
    logPath: "/tmp/synthetic-handoff.log",
  })),
}));

const state = {
  installed: true,
  loadState: { status: "loaded" },
  running: true,
  env: {},
  command: null,
  runtime: { status: "running", pid: 1 },
} satisfies GatewayServiceState;
const stopProgress = vi.fn();
const handoff = (canaryTimeout?: string) =>
  handoffUpdateFromGateway({
    state,
    root: "/opt/openclaw",
    mode: "npm",
    opts: { canaryTimeout },
    timeoutMs: 1_800_000,
    stopProgress,
  });

afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

it.runIf(process.platform === "linux" || process.platform === "darwin").each([
  { canaryTimeout: "600", expected: 600_000 },
  { canaryTimeout: undefined, expected: undefined },
])(
  "preserves public timeout options at the shared handoff owner: %j",
  async ({ canaryTimeout, expected }) => {
    vi.stubEnv("OPENCLAW_UPDATE_RUN_HANDOFF", "");
    await expect(handoff(canaryTimeout)).rejects.toMatchObject({
      reason: "managed-service-handoff-already-running",
    });
    expect(startManagedServiceUpdateHandoff).toHaveBeenCalledWith(
      expect.objectContaining({ timeoutMs: 1_800_000, canaryTimeoutMs: expected }),
    );
  },
);

it("rejects invalid canary timeouts before handoff side effects", async () => {
  await expect(handoff("0")).rejects.toThrow(
    "--canary-timeout must be a positive integer (seconds)",
  );
  expect(stopProgress).not.toHaveBeenCalled();
  expect(startManagedServiceUpdateHandoff).not.toHaveBeenCalled();
});
