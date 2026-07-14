ALTER TABLE analysis_jobs
    ADD COLUMN provider VARCHAR(64) NULL,
    ADD COLUMN result_object_key VARCHAR(1024) NULL,
    ADD COLUMN result_preview TEXT NULL;
