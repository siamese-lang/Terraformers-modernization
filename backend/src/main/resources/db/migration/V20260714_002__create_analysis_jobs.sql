CREATE TABLE analysis_jobs (
    id VARCHAR(36) NOT NULL,
    project_id BIGINT NOT NULL,
    source_file_id BIGINT NOT NULL,
    result_file_id BIGINT NULL,
    source_bucket VARCHAR(255) NOT NULL,
    source_key VARCHAR(1024) NOT NULL,
    correlation_id VARCHAR(128),
    status VARCHAR(32) NOT NULL,
    analysis_mode VARCHAR(32) NOT NULL,
    provider VARCHAR(64),
    result_object_key VARCHAR(1024),
    result_preview TEXT,
    failure_reason VARCHAR(2000),
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT fk_analysis_jobs_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id),
    CONSTRAINT fk_analysis_jobs_source_file
        FOREIGN KEY (source_file_id) REFERENCES project_files (file_id),
    CONSTRAINT fk_analysis_jobs_result_file
        FOREIGN KEY (result_file_id) REFERENCES project_files (file_id),
    INDEX idx_analysis_jobs_project_created (project_id, created_at),
    INDEX idx_analysis_jobs_source_file (source_file_id),
    INDEX idx_analysis_jobs_result_file (result_file_id),
    INDEX idx_analysis_jobs_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
