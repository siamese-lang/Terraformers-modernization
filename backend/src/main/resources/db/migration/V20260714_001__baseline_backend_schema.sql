CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT NOT NULL AUTO_INCREMENT,
    cognito_subject VARCHAR(128) NOT NULL,
    email VARCHAR(255),
    display_name VARCHAR(100),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id),
    UNIQUE KEY uk_users_cognito_subject (cognito_subject)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS projects (
    project_id BIGINT NOT NULL AUTO_INCREMENT,
    owner_user_id BIGINT NOT NULL,
    project_name VARCHAR(200) NOT NULL,
    visibility VARCHAR(30) NOT NULL DEFAULT 'PRIVATE',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (project_id),
    KEY idx_projects_owner_user_id (owner_user_id),
    KEY idx_projects_visibility (visibility),
    CONSTRAINT fk_projects_owner_user
        FOREIGN KEY (owner_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS project_files (
    file_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    s3_bucket VARCHAR(255) NOT NULL,
    s3_key VARCHAR(1024) NOT NULL,
    content_type VARCHAR(100),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (file_id),
    KEY idx_project_files_project_id (project_id),
    CONSTRAINT fk_project_files_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS boards (
    board_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    board_type VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (board_id),
    UNIQUE KEY uk_boards_project_type (project_id, board_type),
    CONSTRAINT fk_boards_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS comments (
    comment_id BIGINT NOT NULL AUTO_INCREMENT,
    board_id BIGINT NOT NULL,
    writer_user_id BIGINT NOT NULL,
    content TEXT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    deleted_at DATETIME(6),
    PRIMARY KEY (comment_id),
    KEY idx_comments_board_id (board_id),
    KEY idx_comments_writer_user_id (writer_user_id),
    CONSTRAINT fk_comments_board
        FOREIGN KEY (board_id) REFERENCES boards (board_id),
    CONSTRAINT fk_comments_writer_user
        FOREIGN KEY (writer_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS board_reactions (
    reaction_id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    board_id BIGINT NOT NULL,
    reaction_type VARCHAR(30) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (reaction_id),
    CONSTRAINT fk_board_reactions_user
        FOREIGN KEY (user_id) REFERENCES users (user_id),
    CONSTRAINT fk_board_reactions_board
        FOREIGN KEY (board_id) REFERENCES boards (board_id),
    CONSTRAINT uk_board_reactions_user_board_type
        UNIQUE (user_id, board_id, reaction_type),
    KEY idx_board_reactions_user_id (user_id),
    KEY idx_board_reactions_board_id (board_id),
    KEY idx_board_reactions_board_reaction_type (board_id, reaction_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS terraform_runs (
    run_id BIGINT NOT NULL AUTO_INCREMENT,
    project_id BIGINT NOT NULL,
    requested_by_user_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    log_queue_url_hash VARCHAR(128),
    tfstate_s3_bucket VARCHAR(255),
    tfstate_s3_key VARCHAR(1024),
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (run_id),
    KEY idx_terraform_runs_project_id (project_id),
    KEY idx_terraform_runs_status (status),
    CONSTRAINT fk_terraform_runs_project
        FOREIGN KEY (project_id) REFERENCES projects (project_id),
    CONSTRAINT fk_terraform_runs_requested_by
        FOREIGN KEY (requested_by_user_id) REFERENCES users (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
