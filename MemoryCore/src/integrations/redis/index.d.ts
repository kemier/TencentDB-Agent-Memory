/**
 * Type-only stub for the private Redis state-backend integration submodule.
 *
 * The real `src/integrations/` is a private deployment submodule not bundled
 * with the public build. Imported only via runtime-guarded dynamic import()
 * inside try/catch (`createStateBackend` throws a clear error when absent).
 * This file has zero runtime effect.
 */

import type { IStateBackend, TaskPayload } from "../../core/state/types.js";

export interface RedisStateBackendOptions {
  client: unknown;
  keyPrefix?: string;
  consumerGroup?: string;
}

export class RedisStateBackend implements IStateBackend {
  constructor(opts: RedisStateBackendOptions);
  appendBuffer(instanceId: string, sessionId: string, message: string, teamId?: string, agentId?: string): Promise<void>;
  drainBuffer(instanceId: string, sessionId: string, teamId?: string, agentId?: string): Promise<string[]>;
  getBufferLength(instanceId: string, sessionId: string, teamId?: string, agentId?: string): Promise<number>;
  getSessionState(
    instanceId: string,
    sessionId: string,
    teamId?: string,
    agentId?: string,
  ): Promise<import("../../core/state/types.js").PipelineSessionState | null>;
  updateSessionState(
    instanceId: string,
    sessionId: string,
    patch: Partial<import("../../core/state/types.js").PipelineSessionState>,
    teamId?: string,
    agentId?: string,
  ): Promise<void>;
  deleteSessionState(instanceId: string, sessionId: string, teamId?: string, agentId?: string): Promise<void>;
  listActiveSessions(instanceId: string): Promise<string[]>;
  setTimer(instanceId: string, member: string, fireAtMs: number): Promise<void>;
  setTimerIfEarlier(instanceId: string, member: string, fireAtMs: number): Promise<boolean>;
  removeTimer(instanceId: string, member: string): Promise<void>;
  getExpiredTimers(
    instanceId: string,
    nowMs: number,
  ): Promise<import("../../core/state/types.js").TimerEntry[]>;
  enqueueTask(task: TaskPayload): Promise<void>;
  consumeTask(workerId: string, blockMs?: number): Promise<TaskPayload | null>;
  ackTask(taskId: string): Promise<void>;
  getQueueDepth(): Promise<{ high: number; low: number }>;
  listQueuedTasks?(): Promise<TaskPayload[]>;
  claimStaleTasks?(workerId: string, minIdleMs: number, count: number): Promise<TaskPayload[]>;
  acquireLock(key: string, ownerId: string, ttlMs: number): Promise<boolean>;
  renewLock(key: string, ownerId: string, ttlMs: number): Promise<boolean>;
  releaseLock(key: string, ownerId: string): Promise<void>;
  captureAtomic(
    params: import("../../core/state/types.js").CaptureAtomicParams,
  ): Promise<import("../../core/state/types.js").CaptureAtomicResult>;
  purgeInstance?(instanceId: string): Promise<{ sessions: number; timers: number; buffers: number }>;
  initialize(): Promise<void>;
  destroy?(): Promise<void>;
  getClient(): unknown;
}
