/**
 * Type-only stub for the private observability integration submodule.
 *
 * The real `src/integrations/` is a private deployment submodule not bundled
 * with the public build. Imported only via runtime-guarded dynamic import()
 * inside try/catch (`loadInternalBackend` returns null when absent). This
 * file has zero runtime effect.
 */

import type { ObservabilityConfig, IObservabilityBackend } from "../../core/report/types.js";

export function createInternalObservabilityBackend(
  config: ObservabilityConfig,
): Promise<IObservabilityBackend>;
