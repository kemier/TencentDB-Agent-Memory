import { describe, expect, it } from 'vitest';
import {
  readGatewayMemoryUserIdFromMetadata,
  resolveGatewayMemoryUserId,
  writeGatewayMemoryUserIdToMetadata,
} from '../src/panel/domain/gateway-memory-user-id.js';

describe('gateway-memory-user-id', () => {
  it('reads from chat_memory namespace', () => {
    const json = JSON.stringify({
      chat_memory: { gateway_memory_user_id: 'zaedinzeng' },
    });
    expect(readGatewayMemoryUserIdFromMetadata(json)).toBe('zaedinzeng');
  });

  it('prefers asset over agent over team over panel default', () => {
    const meta = (id: string) =>
      JSON.stringify({ chat_memory: { gateway_memory_user_id: id } });
    const uid = resolveGatewayMemoryUserId({
      asset: { owner_user_id: 'usr-cqhmon8pw7', metadata_json: meta('asset-id') },
      agent: { metadata_json: meta('agent-id') },
      team: { metadata_json: meta('team-id') },
      panelDefault: 'zaedinzeng',
    });
    expect(uid).toBe('asset-id');
  });

  it('uses panel default when metadata empty (acp-admin + zaedinzeng case)', () => {
    const uid = resolveGatewayMemoryUserId({
      asset: { owner_user_id: 'usr-cqhmon8pw7' },
      panelDefault: 'zaedinzeng',
    });
    expect(uid).toBe('zaedinzeng');
  });

  it('falls back to owner_user_id when no override', () => {
    const uid = resolveGatewayMemoryUserId({
      asset: { owner_user_id: 'usr-cqhmon8pw7' },
    });
    expect(uid).toBe('usr-cqhmon8pw7');
  });

  it('write round-trips', () => {
    const next = writeGatewayMemoryUserIdToMetadata('{"ui":{}}', 'zaedinzeng');
    expect(readGatewayMemoryUserIdFromMetadata(next)).toBe('zaedinzeng');
    expect(JSON.parse(next).ui).toEqual({});
  });
});
