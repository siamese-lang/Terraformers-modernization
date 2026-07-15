package com.terraformers.modernization.project;

import java.time.Instant;

public record PublicProjectResponse(
        String projectId,
        String id,
        String projectName,
        String name,
        ProjectVisibility visibility,
        boolean isPrivate,
        String imageUrl,
        String description,
        String originalFilename,
        String contentType,
        Long uploadSizeBytes,
        String sourceBucket,
        String sourceKey,
        String sourceStorageProvider,
        boolean sourceBinaryPersisted,
        String sourceETag,
        String latestAnalysisJobId,
        String latestResultObjectKey,
        Instant terraformDraftUpdatedAt,
        Instant createdAt,
        Instant updatedAt,
        String projectTreeApiPath,
        String terraformDraftApiPath
) {
    static PublicProjectResponse from(ProjectResponse project) {
        String projectId = project.projectId();
        String displayName = project.displayName();
        return new PublicProjectResponse(
                projectId,
                projectId,
                displayName,
                displayName,
                project.visibility(),
                project.visibility() != ProjectVisibility.PUBLIC,
                null,
                null,
                project.originalFilename(),
                project.contentType(),
                project.uploadSizeBytes(),
                project.sourceBucket(),
                project.sourceKey(),
                project.sourceStorageProvider(),
                project.sourceBinaryPersisted(),
                project.sourceETag(),
                project.latestAnalysisJobId(),
                project.latestResultObjectKey(),
                project.terraformDraftUpdatedAt(),
                project.createdAt(),
                project.updatedAt(),
                "/api/project-tree/" + projectId,
                "/api/projects/" + projectId + "/terraform/main.tf"
        );
    }
}
