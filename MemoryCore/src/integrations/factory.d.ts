/**
 * Type-only stub for the private adapter-factory integration submodule.
 *
 * The real `src/integrations/` is a private deployment submodule not bundled
 * with the public build. Imported only via runtime-guarded dynamic import()
 * inside try/catch (gateway falls back to LocalConfigSource + NoopQuotaReporter
 * in standalone mode when absent, and fails fast in service mode). This file
 * has zero runtime effect.
 */

import type {
  IConfigSource,
  IQuotaReporter,
} from "../../core/abstractions/index.js";
import type { Logger } from "../../core/types.js";

export interface CreateAdapterDepsOptions {
  deployMode: string;
  sharkBaseUrl?: string;
  logger: Logger;
}

export function createAdapterDeps(opts: CreateAdapterDepsOptions): Promise<{
  configSource: IConfigSource;
  quotaReporter: IQuotaReporter;
}>;
