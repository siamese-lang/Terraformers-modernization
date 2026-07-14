CREATE TABLE analysis_jobs (
    id VARCHAR(36) NOT NULL,
    project_id VARCHAR(64) NOT NULL,
    source_bucket VARCHAR(255) NOT NULL,
    source_key VARCHAR(1024) NOT NULL,
    correlation_id VARCHAR(128),
    status VARCHAR(32) NOT NULL,
    analysis_mode VARCHAR(32) NOT NULL,
    failure_reason VARCHAR(2000),
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (id),
    INDEX idx_analysis_jobs_project_id (project_id),
    INDEX idx_analysis_jobs_status (status),
    INDEX idx_analysis_jobs_created_at (created_at)
);
