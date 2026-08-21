import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import pg from "pg";
import type { AppConfig } from "./config.js";
import type { CreateJobInput, Job, JobError, JobOutput, JobPatch, JobStatus } from "./types.js";

const { Pool } = pg;

export interface JobRepository {
  initialize(): Promise<void>;
  close(): Promise<void>;
  create(input: CreateJobInput): Promise<Job>;
  get(id: string): Promise<Job | undefined>;
  getByRequestId(requestId: string): Promise<Job | undefined>;
  update(id: string, patch: JobPatch): Promise<Job>;
  listRecoverable(): Promise<Job[]>;
}

export class MemoryJobRepository implements JobRepository {
  readonly #jobs = new Map<string, Job>();

  async initialize(): Promise<void> {}
  async close(): Promise<void> {}

  async create(input: CreateJobInput): Promise<Job> {
    const existing = await this.getByRequestId(input.requestId);
    if (existing) return existing;

    const now = new Date();
    const job: Job = {
      id: randomUUID(),
      requestId: input.requestId,
      playerUserId: input.playerUserId,
      kind: input.kind,
      status: "QUEUED",
      stage: "Waiting for a worker",
      progress: 0,
      filteredPrompt: input.filteredPrompt,
      accessoryType: input.accessoryType,
      ...(input.sourceJobId ? { sourceJobId: input.sourceJobId } : {}),
      priority: input.priority,
      context: structuredClone(input.context),
      output: {},
      createdAt: now,
      updatedAt: now,
    };
    this.#jobs.set(job.id, cloneJob(job));
    return cloneJob(job);
  }

  async get(id: string): Promise<Job | undefined> {
    const job = this.#jobs.get(id);
    return job ? cloneJob(job) : undefined;
  }

  async getByRequestId(requestId: string): Promise<Job | undefined> {
    for (const job of this.#jobs.values()) {
      if (job.requestId === requestId) return cloneJob(job);
    }
    return undefined;
  }

  async update(id: string, patch: JobPatch): Promise<Job> {
    const existing = this.#jobs.get(id);
    if (!existing) throw new Error(`Job ${id} not found`);
    const next = cloneJob({ ...existing, ...patch, updatedAt: patch.updatedAt ?? new Date() });
    this.#jobs.set(id, next);
    return cloneJob(next);
  }

  async listRecoverable(): Promise<Job[]> {
    return [...this.#jobs.values()]
      .filter((job) => !["SUCCEEDED", "FAILED", "IMAGE_READY"].includes(job.status))
      .sort((left, right) => Number(right.priority) - Number(left.priority) || left.createdAt.getTime() - right.createdAt.getTime())
      .map(cloneJob);
  }
}

type JobRow = {
  id: string;
  request_id: string;
  player_user_id: string;
  kind: Job["kind"];
  status: JobStatus;
  stage: string;
  progress: number;
  filtered_prompt: string;
  accessory_type: Job["accessoryType"];
  source_job_id: string | null;
  priority: boolean;
  context: Job["context"];
  output: JobOutput;
  error: JobError | null;
  image_artifact: Buffer | null;
  created_at: Date;
  updated_at: Date;
};

export class PostgresJobRepository implements JobRepository {
  readonly #pool: pg.Pool;

  constructor(config: AppConfig) {
    if (!config.databaseUrl) throw new Error("databaseUrl is required");
    this.#pool = new Pool({
      connectionString: config.databaseUrl,
      ssl: config.databaseSsl ? { rejectUnauthorized: false } : false,
      max: 8,
    });
  }

  async initialize(): Promise<void> {
    const migrationPath = fileURLToPath(new URL("../migrations/001_jobs.sql", import.meta.url));
    const sql = await readFile(migrationPath, "utf8");
    await this.#pool.query(sql);
  }

  async close(): Promise<void> {
    await this.#pool.end();
  }

  async create(input: CreateJobInput): Promise<Job> {
    const id = randomUUID();
    const result = await this.#pool.query<JobRow>(
      `INSERT INTO forge_jobs (
         id, request_id, player_user_id, kind, status, stage, progress,
         filtered_prompt, accessory_type, source_job_id, priority, context
       ) VALUES ($1, $2, $3, $4, 'QUEUED', 'Waiting for a worker', 0, $5, $6, $7, $8, $9)
       ON CONFLICT (request_id) DO UPDATE SET request_id = EXCLUDED.request_id
       RETURNING *`,
      [
        id,
        input.requestId,
        input.playerUserId,
        input.kind,
        input.filteredPrompt,
        input.accessoryType,
        input.sourceJobId ?? null,
        input.priority,
        input.context,
      ],
    );
    return rowToJob(requiredRow(result.rows[0]));
  }

  async get(id: string): Promise<Job | undefined> {
    const result = await this.#pool.query<JobRow>("SELECT * FROM forge_jobs WHERE id = $1", [id]);
    return result.rows[0] ? rowToJob(result.rows[0]) : undefined;
  }

  async getByRequestId(requestId: string): Promise<Job | undefined> {
    const result = await this.#pool.query<JobRow>("SELECT * FROM forge_jobs WHERE request_id = $1", [requestId]);
    return result.rows[0] ? rowToJob(result.rows[0]) : undefined;
  }

  async update(id: string, patch: JobPatch): Promise<Job> {
    const current = await this.get(id);
    if (!current) throw new Error(`Job ${id} not found`);
    const next: Job = { ...current, ...patch, updatedAt: patch.updatedAt ?? new Date() };
    const result = await this.#pool.query<JobRow>(
      `UPDATE forge_jobs SET
         status = $2, stage = $3, progress = $4, output = $5, error = $6,
         image_artifact = $7, updated_at = $8
       WHERE id = $1 RETURNING *`,
      [
        id,
        next.status,
        next.stage,
        next.progress,
        next.output,
        next.error ?? null,
        next.imageArtifact ?? null,
        next.updatedAt,
      ],
    );
    return rowToJob(requiredRow(result.rows[0]));
  }

  async listRecoverable(): Promise<Job[]> {
    const result = await this.#pool.query<JobRow>(
      `SELECT * FROM forge_jobs
       WHERE status NOT IN ('SUCCEEDED', 'FAILED', 'IMAGE_READY')
       ORDER BY priority DESC, created_at ASC
       LIMIT 500`,
    );
    return result.rows.map(rowToJob);
  }
}

export function createRepository(config: AppConfig): JobRepository {
  return config.databaseUrl ? new PostgresJobRepository(config) : new MemoryJobRepository();
}

function requiredRow(row: JobRow | undefined): JobRow {
  if (!row) throw new Error("Database write returned no row");
  return row;
}

function rowToJob(row: JobRow): Job {
  return {
    id: row.id,
    requestId: row.request_id,
    playerUserId: Number(row.player_user_id),
    kind: row.kind,
    status: row.status,
    stage: row.stage,
    progress: row.progress,
    filteredPrompt: row.filtered_prompt,
    accessoryType: row.accessory_type,
    ...(row.source_job_id ? { sourceJobId: row.source_job_id } : {}),
    priority: row.priority,
    context: row.context,
    output: row.output ?? {},
    ...(row.error ? { error: row.error } : {}),
    ...(row.image_artifact ? { imageArtifact: Buffer.from(row.image_artifact) } : {}),
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
  };
}

function cloneJob(job: Job): Job {
  const { imageArtifact, ...withoutArtifact } = job;
  return {
    ...structuredClone(withoutArtifact),
    ...(imageArtifact ? { imageArtifact: Buffer.from(imageArtifact) } : {}),
    createdAt: new Date(job.createdAt),
    updatedAt: new Date(job.updatedAt),
  };
}
