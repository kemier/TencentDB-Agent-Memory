/**
 * Gateway data-plane user_id for chat_memory (L0/L1/L2/L3).
 *
 * Panel meta users (e.g. usr-cqhmon8pw7 / acp-admin) differ from ACP capture
 * identity (e.g. zaedinzeng in acp.memory.userId). ACL still uses owner_user_id;
 * reads/writes to MemoryCore use gateway_memory_user_id when configured.
 *
 * Resolution order (first non-empty wins):
 *   1. asset.metadata_json.chat_memory.gateway_memory_user_id
 *   2. agent.metadata_json.chat_memory.gateway_memory_user_id
 *   3. team.metadata_json.chat_memory.gateway_memory_user_id
 *   4. Panel env DEFAULT_GATEWAY_MEMORY_USER_ID
 *   5. asset.owner_user_id (legacy fallback)
 */

const METADATA_NS = 'chat_memory';
const FIELD = 'gateway_memory_user_id';

export interface MetadataCarrier {
  metadata_json?: string;
}

export interface GatewayMemoryUserIdScope {
  asset: MetadataCarrier & { owner_user_id: string };
  agent?: MetadataCarrier;
  team?: MetadataCarrier;
  panelDefault?: string;
}

/** Read gateway_memory_user_id from a metadata_json blob (asset / agent / team). */
export function readGatewayMemoryUserIdFromMetadata(
  metadataJson?: string,
): string | undefined {
  if (!metadataJson) return undefined;
  try {
    const meta = JSON.parse(metadataJson) as Record<string, unknown>;
    const slot = meta?.[METADATA_NS];
    if (!slot || typeof slot !== 'object') return undefined;
    const raw = (slot as Record<string, unknown>)[FIELD];
    if (typeof raw !== 'string') return undefined;
    const trimmed = raw.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  } catch {
    return undefined;
  }
}

/** Merge gateway_memory_user_id into metadata_json.chat_memory (returns new JSON). */
export function writeGatewayMemoryUserIdToMetadata(
  prevMetadataJson: string | undefined,
  gatewayMemoryUserId: string,
): string {
  let meta: Record<string, unknown> = {};
  if (prevMetadataJson) {
    try {
      const parsed = JSON.parse(prevMetadataJson);
      if (parsed && typeof parsed === 'object') meta = parsed as Record<string, unknown>;
    } catch {
      /* discard */
    }
  }
  const slot =
    meta[METADATA_NS] && typeof meta[METADATA_NS] === 'object'
      ? { ...(meta[METADATA_NS] as Record<string, unknown>) }
      : {};
  slot[FIELD] = gatewayMemoryUserId.trim();
  meta[METADATA_NS] = slot;
  return JSON.stringify(meta);
}

/**
 * Resolve the MemoryCore user_id for chat_memory data-plane calls.
 */
export function resolveGatewayMemoryUserId(scope: GatewayMemoryUserIdScope): string {
  const fromAsset = readGatewayMemoryUserIdFromMetadata(scope.asset.metadata_json);
  if (fromAsset) return fromAsset;

  const fromAgent = readGatewayMemoryUserIdFromMetadata(scope.agent?.metadata_json);
  if (fromAgent) return fromAgent;

  const fromTeam = readGatewayMemoryUserIdFromMetadata(scope.team?.metadata_json);
  if (fromTeam) return fromTeam;

  const panelDefault = scope.panelDefault?.trim();
  if (panelDefault) return panelDefault;

  return scope.asset.owner_user_id;
}

/** Alias for agent/asset metadata updates. */
export const writeAgentGatewayMemoryUserId = writeGatewayMemoryUserIdToMetadata;
