-- Compatibility migration retained for databases that applied an earlier
-- analysis_jobs table without the result fields. The current 002 baseline
-- already includes these columns, so a clean database treats this migration
-- as an idempotent no-op.
ALTER TABLE analysis_jobs
    ADD COLUMN IF NOT EXISTS provider VARCHAR(64) NULL,
    ADD COLUMN IF NOT EXISTS result_object_key VARCHAR(1024) NULL,
    ADD COLUMN IF NOT EXISTS result_preview TEXT NULL;
