CREATE TABLE users (
    user_id BIGINT NOT NULL AUTO_INCREMENT,
    cognito_sub VARCHAR(128) NOT NULL,
    email VARCHAR(320) NULL,
    display_name VARCHAR(100) NULL,
    role VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (user_id),
    CONSTRAINT uk_users_cognito_sub UNIQUE (cognito_sub),
    CONSTRAINT uk_users_email UNIQUE (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE projects (
    project_id BIGINT NOT NULL AUTO_INCREMENT,
    owner_user_id BIGINT NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT NULL,
    visibility VARCHAR(20) NOT NULL,
    status VARCHAR(30) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    deleted_at TIMESTAMP(6) NULL,
    PRIMARY KEY (project_id),
    CONSTRAINT fk_projects_owner_user
        FOREIGN KEY (owner_user_id) REFERENCES users (user_id),
    KEY idx_projects_owner_deleted_created (owner_user_id, deleted_at, created_at),
    KEY idx_projects_visibility_deleted_created (visibility, deleted_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE project_files (
    file_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    parent_file_id BIGINT NULL,
    uploaded_by BIGINT NULL,
    node_type VARCHAR(20) NOT NULL,
    file_type VARCHAR(50) NULL,
    path VARCHAR(1024) NOT NULL,
    sort_order INT NOT NULL,
    original_filename VARCHAR(255) NULL,
    s3_bucket VARCHAR(255) NULL,
    s3_key VARCHAR(1024) NULL,
    storage_provider VARCHAR(64) NULL,
    binary_persisted BOOLEAN NOT NULL DEFAULT FALSE,
    storage_etag VARCHAR(255) NULL,
    content_type VARCHAR(255) NULL,
    size_bytes BIGINT NULL,
    checksum VARCHAR(128) NULL,
    inline_content LONGTEXT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    deleted_at TIMESTAMP(6) NULL,
    PRIMARY KEY (file_id),
    CONSTRAINT fk_project_files_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id),
    CONSTRAINT fk_project_files_parent_file
        FOREIGN KEY (parent_file_id) REFERENCES project_files (file_id),
    CONSTRAINT fk_project_files_uploaded_by
        FOREIGN KEY (uploaded_by) REFERENCES users (user_id),
    KEY idx_project_files_project_deleted_sort_created
        (project_id, deleted_at, sort_order, created_at),
    KEY idx_project_files_project_parent_deleted_sort_created
        (project_id, parent_file_id, deleted_at, sort_order, created_at),
    KEY idx_project_files_project_type_deleted_created
        (project_id, file_type, deleted_at, created_at),
    KEY idx_project_files_project_path_prefix_deleted
        (project_id, path(255), deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE terraform_runs (
    run_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    requested_by BIGINT NULL,
    run_type VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    request_message_id VARCHAR(255) NULL,
    result_summary TEXT NULL,
    log_s3_key VARCHAR(1024) NULL,
    started_at TIMESTAMP(6) NULL,
    finished_at TIMESTAMP(6) NULL,
    error_message TEXT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (run_id),
    CONSTRAINT fk_terraform_runs_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id),
    CONSTRAINT fk_terraform_runs_requested_by
        FOREIGN KEY (requested_by) REFERENCES users (user_id),
    KEY idx_terraform_runs_project_created_desc (project_id, created_at),
    KEY idx_terraform_runs_project_status_created (project_id, status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE boards (
    board_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    writer_user_id BIGINT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content MEDIUMTEXT NOT NULL,
    category VARCHAR(30) NULL,
    status VARCHAR(30) NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    deleted_at TIMESTAMP(6) NULL,
    PRIMARY KEY (board_id),
    CONSTRAINT fk_boards_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id),
    CONSTRAINT fk_boards_writer_user
        FOREIGN KEY (writer_user_id) REFERENCES users (user_id),
    KEY idx_boards_project_deleted_created (project_id, deleted_at, created_at),
    KEY idx_boards_author_deleted_created (writer_user_id, deleted_at, created_at),
    KEY idx_boards_project_category_deleted_created
        (project_id, category, deleted_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE comments (
    comment_id BIGINT NOT NULL AUTO_INCREMENT,
    board_id BIGINT NOT NULL,
    writer_user_id BIGINT NOT NULL,
    parent_comment_id BIGINT NULL,
    content TEXT NOT NULL,
    status VARCHAR(30) NULL,
    created_at TIMESTAMP(6) NOT NULL,
    updated_at TIMESTAMP(6) NOT NULL,
    deleted_at TIMESTAMP(6) NULL,
    PRIMARY KEY (comment_id),
    CONSTRAINT fk_comments_board
        FOREIGN KEY (board_id) REFERENCES boards (board_id),
    CONSTRAINT fk_comments_writer_user
        FOREIGN KEY (writer_user_id) REFERENCES users (user_id),
    CONSTRAINT fk_comments_parent_comment
        FOREIGN KEY (parent_comment_id) REFERENCES comments (comment_id),
    KEY idx_comments_board_deleted_created (board_id, deleted_at, created_at),
    KEY idx_comments_board_parent_deleted_created
        (board_id, parent_comment_id, deleted_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE board_reactions (
    reaction_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    board_id BIGINT NOT NULL,
    reaction_type VARCHAR(30) NOT NULL,
    created_at TIMESTAMP(6) NOT NULL,
    PRIMARY KEY (reaction_id),
    CONSTRAINT fk_board_reactions_user
        FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT fk_board_reactions_board
        FOREIGN KEY (board_id) REFERENCES boards (board_id),
    CONSTRAINT uk_board_reactions_user_board_type
        UNIQUE (user_id, board_id, reaction_type),
    KEY idx_board_reactions_board_reaction_type (board_id, reaction_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
