package com.terraformers.modernization.project;

import com.terraformers.modernization.analysis.AnalysisJobEntity;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import java.time.Instant;

public record ProjectResponse(
        Long projectId,
        String displayName,
        String description,
        ProjectVisibility visibility,
        String latestAnalysisJobId,
        Long latestResultFileId,
        String latestResultObjectKey,
        Instant terraformDraftUpdatedAt,
        Long sourceFileId,
        String sourceBucket,
        String sourceKey,
        String sourceStorageProvider,
        boolean sourceBinaryPersisted,
        String sourceETag,
        String originalFilename,
        String contentType,
        Long uploadSizeBytes,
        Instant createdAt,
        Instant updatedAt
) {
    public static ProjectResponse from(
            OwnedProjectEntity project,
            ProjectFileEntity sourceFile,
            ProjectFileEntity terraformFile,
            AnalysisJobEntity latestJob
    ) {
        return new ProjectResponse(
                project.getProjectId(),
                project.getName(),
                project.getDescription(),
                project.getVisibility(),
                latestJob == null ? null : latestJob.getId(),
                terraformFile == null ? null : terraformFile.getFileId(),
                terraformFile == null ? null : terraformFile.getS3Key(),
                terraformFile == null ? null : terraformFile.getUpdatedAt(),
                sourceFile == null ? null : sourceFile.getFileId(),
                sourceFile == null ? null : sourceFile.getS3Bucket(),
                sourceFile == null ? null : sourceFile.getS3Key(),
                sourceFile == null ? null : sourceFile.getStorageProvider(),
                sourceFile != null && sourceFile.isBinaryPersisted(),
                sourceFile == null ? null : sourceFile.getStorageETag(),
                sourceFile == null ? null : sourceFile.getOriginalFilename(),
                sourceFile == null ? null : sourceFile.getContentType(),
                sourceFile == null ? null : sourceFile.getSizeBytes(),
                project.getCreatedAt(),
                project.getUpdatedAt()
        );
    }
}
