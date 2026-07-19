package com.terraformers.modernization.project;

import java.time.Instant;

public record PublicProjectResponse(
        Long projectId,
        Long id,
        String projectName,
        String name,
        ProjectVisibility visibility,
        boolean isPrivate,
        String imageUrl,
        String description,
        Long sourceFileId,
        String originalFilename,
        String contentType,
        Long uploadSizeBytes,
        String sourceBucket,
        String sourceKey,
        String sourceStorageProvider,
        boolean sourceBinaryPersisted,
        String sourceETag,
        String latestAnalysisJobId,
        Long latestResultFileId,
        String latestResultObjectKey,
        Instant terraformDraftUpdatedAt,
        Instant createdAt,
        Instant updatedAt,
        String projectTreeApiPath,
        String terraformDraftApiPath
) {
    static PublicProjectResponse from(ProjectResponse project) {
        Long projectId = project.projectId();
        String displayName = project.displayName();
        return new PublicProjectResponse(
                projectId,
                projectId,
                displayName,
                displayName,
                project.visibility(),
                project.visibility() != ProjectVisibility.PUBLIC,
                project.sourceFileId() != null && project.sourceBinaryPersisted()
                        ? "/api/projects/" + projectId + "/source-image"
                        : null,
                project.description(),
                project.sourceFileId(),
                project.originalFilename(),
                project.contentType(),
                project.uploadSizeBytes(),
                project.sourceBucket(),
                project.sourceKey(),
                project.sourceStorageProvider(),
                project.sourceBinaryPersisted(),
                project.sourceETag(),
                project.latestAnalysisJobId(),
                project.latestResultFileId(),
                project.latestResultObjectKey(),
                project.terraformDraftUpdatedAt(),
                project.createdAt(),
                project.updatedAt(),
                "/api/project-tree/" + projectId,
                "/api/projects/" + projectId + "/terraform/main.tf"
        );
    }
}
