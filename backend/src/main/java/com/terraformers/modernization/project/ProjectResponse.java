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
        String provider,
        String failureReason,
        Long resultFileId,
        Long latestResultFileId,
        String latestResultObjectKey,
        String analysisStatus,
        String analysisSummary,
        java.util.List<String> detectedComponents,
        java.util.List<String> detectedRelationships,
        java.util.List<String> warnings,
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
                latestJob == null ? null : latestJob.getProvider(),
                latestJob == null ? null : latestJob.getFailureReason(),
                latestJob == null ? null : latestJob.getResultFileId(),
                terraformFile == null ? null : terraformFile.getFileId(),
                terraformFile == null ? null : terraformFile.getS3Key(),
                latestJob == null ? null : latestJob.getStatus().name(),
                latestJob == null ? null : latestJob.getAnalysisSummary(),
                splitLines(latestJob == null ? null : latestJob.getDetectedComponents()),
                splitLines(latestJob == null ? null : latestJob.getDetectedRelationships()),
                splitLines(latestJob == null ? null : latestJob.getAnalysisWarnings()),
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

    private static java.util.List<String> splitLines(String value) {
        if (value == null || value.isBlank()) {
            return java.util.List.of();
        }
        return java.util.Arrays.stream(value.split("\\R")).map(String::strip).filter(line -> !line.isBlank()).toList();
    }
}
