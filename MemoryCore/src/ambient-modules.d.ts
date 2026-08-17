/**
 * Ambient type declarations for optional / private-module dependencies.
 *
 * These modules are NOT present in this repo (or are optional packages that
 * may not be installed), but are referenced via runtime-guarded dynamic
 * imports and type-only annotations:
 *
 * - `src/integrations/*`  — private deployment submodule (COS backend, Redis
 *   state backend, observability backend, adapter factory). Absent from the
 *   open build; all imports are inside try/catch + dynamic import() or are
 *   type-only, so a missing module at runtime falls back gracefully.
 * - `openclaw/plugin-sdk/core` — optional OpenClaw host SDK (type-only import).
 * - `node-llama-cpp` — optional local embedding runtime (dynamic import,
 *   overridable for tests).
 *
 * The declarations below mirror the exact shapes consumed by the code so the
 * type check passes without those modules installed. They add no runtime code.
 */

declare module "openclaw/plugin-sdk/core" {
  import type { Logger } from "../core/types.js";

  // Minimal shape used by the code: only `runtime.agent.runEmbeddedPiAgent`.
  export interface OpenClawPluginApi {
    logger: Logger;
    runtime: {
      agent: {
        runEmbeddedPiAgent: (opts: unknown) => Promise<unknown>;
      };
    };
  }
}

declare module "node-llama-cpp" {
  export interface LlamaOptions {
    logLevel: number;
  }
  export function getLlama(opts: LlamaOptions): Promise<unknown>;
  export function resolveModelFile(model: string, cacheDir?: string): Promise<string>;
  export const LlamaLogLevel: { error: number };
}
