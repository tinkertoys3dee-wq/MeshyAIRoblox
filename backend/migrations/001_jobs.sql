CREATE TABLE IF NOT EXISTS forge_jobs (
  id UUID PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  player_user_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  stage TEXT NOT NULL,
  progress INTEGER NOT NULL DEFAULT 0,
  filtered_prompt TEXT NOT NULL,
  accessory_type TEXT NOT NULL,
  style_preset TEXT NOT NULL DEFAULT 'AUTO',
  detail_level TEXT NOT NULL DEFAULT 'BALANCED',
  source_job_id UUID NULL REFERENCES forge_jobs(id),
  source_image_asset_id BIGINT NULL,
  priority BOOLEAN NOT NULL DEFAULT FALSE,
  context JSONB NOT NULL DEFAULT '{}'::jsonb,
  output JSONB NOT NULL DEFAULT '{}'::jsonb,
  error JSONB NULL,
  image_artifact BYTEA NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT forge_jobs_progress CHECK (progress >= 0 AND progress <= 100)
);

ALTER TABLE forge_jobs ADD COLUMN IF NOT EXISTS style_preset TEXT NOT NULL DEFAULT 'AUTO';
ALTER TABLE forge_jobs ADD COLUMN IF NOT EXISTS detail_level TEXT NOT NULL DEFAULT 'BALANCED';
ALTER TABLE forge_jobs ADD COLUMN IF NOT EXISTS source_image_asset_id BIGINT NULL;

CREATE INDEX IF NOT EXISTS forge_jobs_player_created_idx
  ON forge_jobs (player_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS forge_jobs_recovery_idx
  ON forge_jobs (status, priority DESC, created_at ASC)
  WHERE status NOT IN ('SUCCEEDED', 'FAILED', 'IMAGE_READY');
