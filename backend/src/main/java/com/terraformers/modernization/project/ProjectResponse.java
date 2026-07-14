package com.terraformers.modernization.project;

import java.time.Instant;

public record ProjectResponse(
        String projectId,
        String displayName,
        ProjectVisibility visibility,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        Instant terraformDraftUpdatedAt,
        String sourceBucket,
        String sourceKey,
        String originalFilename,
        String contentType,
        Long uploadSizeBytes,
        Instant createdAt,
        Instant updatedAt
) {
    static ProjectResponse from(ProjectEntity entity) {
        return new ProjectResponse(
                entity.getProjectId(),
                entity.getDisplayName(),
                entity.getVisibility(),
                entity.getLatestAnalysisJobId(),
                entity.getLatestResultObjectKey(),
                entity.getTerraformDraftUpdatedAt(),
                entity.getSourceBucket(),
                entity.getSourceKey(),
                entity.getOriginalFilename(),
                entity.getContentType(),
                entity.getUploadSizeBytes(),
                entity.getCreatedAt(),
                entity.getUpdatedAt()
        );
    }
}
