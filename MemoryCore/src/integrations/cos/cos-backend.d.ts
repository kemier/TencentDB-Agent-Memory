/**
 * Type-only stub for the private COS integration submodule.
 *
 * The real `src/integrations/` is a private deployment submodule that is NOT
 * bundled with the public build. All imports of it are runtime-guarded:
 * dynamic `import()` inside try/catch, or type-only annotations that are
 * erased at emit. When the real module is absent, the guarded fallback paths
 * execute; when a deployment provides it, the stronger types below still
 * match (implements / structurally compatible).
 *
 * This file has zero runtime effect.
 */

import type {
  IStorageBackend,
  ICredentialProvider,
  StorageLogger,
  StorageObject,
  ListResult,
} from "../../core/storage/types.js";

export interface SharedCosClientOptions {
  credentialProvider: ICredentialProvider;
  logger?: StorageLogger;
  cosEndpointDomain?: string;
}

export class SharedCosClient {
  constructor(opts: SharedCosClientOptions);
  getClient(): Promise<unknown>;
  /** 确保 COS bucket 的生成日志生命周期规则已按保留天数配置（真实私有模块提供） */
  ensureGenerationLogRetention(retentionDays: number): Promise<void>;
}

export interface CosStorageBackendOptions {
  sharedClient?: SharedCosClient;
  credentialProvider?: ICredentialProvider;
  prefix?: string;
  logger?: StorageLogger;
}

export class CosStorageBackend implements IStorageBackend {
  readonly type: "local" | "cos";
  constructor(opts: CosStorageBackendOptions);
  putObject(key: string, content: string | Buffer, opts?: unknown): Promise<void>;
  appendObject(key: string, content: string | Buffer): Promise<void>;
  getObject(key: string): Promise<StorageObject | null>;
  exists(key: string): Promise<boolean>;
  listObjects(prefix: string, opts?: unknown): Promise<ListResult>;
  deleteObject(key: string): Promise<void>;
  deleteByPrefix(prefix: string): Promise<number>;
}
