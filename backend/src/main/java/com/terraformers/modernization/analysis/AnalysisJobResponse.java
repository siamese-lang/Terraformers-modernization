package com.terraformers.modernization.analysis;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;

public record AnalysisJobResponse(
        String id,
        Long projectId,
        Long sourceFileId,
        Long resultFileId,
        String sourceBucket,
        String sourceKey,
        String correlationId,
        AnalysisJobStatus status,
        AnalysisMode analysisMode,
        String provider,
        String resultObjectKey,
        String resultPreview,
        String analysisSummary,
        List<String> detectedComponents,
        List<String> detectedRelationships,
        List<String> warnings,
        String failureReason,
        Instant createdAt,
        Instant updatedAt
) {
    static AnalysisJobResponse from(AnalysisJobEntity entity) {
        return new AnalysisJobResponse(
                entity.getId(),
                entity.getProjectId(),
                entity.getSourceFileId(),
                entity.getResultFileId(),
                entity.getSourceBucket(),
                entity.getSourceKey(),
                entity.getCorrelationId(),
                entity.getStatus(),
                entity.getAnalysisMode(),
                entity.getProvider(),
                entity.getResultObjectKey(),
                entity.getResultPreview(),
                entity.getAnalysisSummary(),
                splitLines(entity.getDetectedComponents()),
                splitLines(entity.getDetectedRelationships()),
                splitLines(entity.getAnalysisWarnings()),
                entity.getFailureReason(),
                entity.getCreatedAt(),
                entity.getUpdatedAt()
        );
    }

    private static List<String> splitLines(String value) {
        if (value == null || value.isBlank()) {
            return List.of();
        }
        return Arrays.stream(value.split("\\R"))
                .map(String::strip)
                .filter(line -> !line.isBlank())
                .toList();
    }
}
