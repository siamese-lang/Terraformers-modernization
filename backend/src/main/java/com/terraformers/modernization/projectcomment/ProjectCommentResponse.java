package com.terraformers.modernization.projectcomment;

import java.time.Instant;

public record ProjectCommentResponse(
        Long id,
        String projectId,
        String content,
        String userEmail,
        Instant createdAt
) {
    static ProjectCommentResponse from(ProjectCommentEntity entity) {
        return new ProjectCommentResponse(
                entity.getId(),
                entity.getProjectId(),
                entity.getContent(),
                entity.getUserEmail(),
                entity.getCreatedAt()
        );
    }
}
