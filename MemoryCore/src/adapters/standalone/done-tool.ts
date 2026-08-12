/**
 * Terminal tool for L2/L3 agent loops — lets the model stop cleanly when
 * toolChoice is "required" (which otherwise forces a tool call every step).
 */

import { tool, jsonSchema } from "ai";

interface Logger {
  debug?: (message: string) => void;
}

const TAG = "[memory-tdai] [done-tool]";

/** No-op tool: call once after the final write/edit to end the tool loop. */
export function createDoneTool(logger?: Logger) {
  return tool({
    description:
      "Signal that all file operations are complete. Call once after your final write or edit. Do not call before writing.",
    inputSchema: jsonSchema<Record<string, never>>({
      type: "object",
      properties: {},
      additionalProperties: false,
    }),
    execute: (async () => {
      logger?.debug?.(`${TAG} done`);
      return JSON.stringify({ success: true, finished: true });
    }) as any,
  });
}
