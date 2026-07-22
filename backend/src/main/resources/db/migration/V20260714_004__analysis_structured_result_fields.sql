ALTER TABLE analysis_jobs
    ADD COLUMN IF NOT EXISTS analysis_summary TEXT NULL,
    ADD COLUMN IF NOT EXISTS detected_components TEXT NULL,
    ADD COLUMN IF NOT EXISTS detected_relationships TEXT NULL,
    ADD COLUMN IF NOT EXISTS analysis_warnings TEXT NULL;
