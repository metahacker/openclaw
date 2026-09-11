import { afterEach, expect, it, vi } from "vitest";
import { assertOpenClawStateWriteAllowedAtPath } from "../../state/openclaw-state-ownership.js";
import { prepareUpdateCommand } from "./update-command-run.js";

vi.mock("../../state/openclaw-state-ownership.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../state/openclaw-state-ownership.js")>()),
  assertOpenClawStateWriteAllowedAtPath: vi.fn(async () => {
    throw new Error("Unexpected state access before argument validation");
  }),
}));

afterEach(() => vi.clearAllMocks());

it.each(["", "0", "-1", "1.5", "1e3", "Infinity", "600s", "9007199254741"])(
  "rejects invalid candidate deadlines before accessing persistent state: %j",
  async (canaryTimeout) => {
    await expect(prepareUpdateCommand({ canaryTimeout })).rejects.toThrow(
      "--canary-timeout must be a positive integer (seconds)",
    );
    expect(assertOpenClawStateWriteAllowedAtPath).not.toHaveBeenCalled();
  },
);
