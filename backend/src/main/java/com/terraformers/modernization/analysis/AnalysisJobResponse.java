package com.terraformers.modernization.analysis;

import java.time.Instant;

public record AnalysisJobResponse(
        String id,
        String projectId,
        String sourceBucket,
        String sourceKey,
        String correlationId,
        AnalysisJobStatus status,
        AnalysisMode analysisMode,
        String provider,
        String resultObjectKey,
        String resultPreview,
        String failureReason,
        Instant createdAt,
        Instant updatedAt
) {
    static AnalysisJobResponse from(AnalysisJobEntity entity) {
        return new AnalysisJobResponse(
                entity.getId(),
                entity.getProjectId(),
                entity.getSourceBucket(),
                entity.getSourceKey(),
                entity.getCorrelationId(),
                entity.getStatus(),
                entity.getAnalysisMode(),
                entity.getProvider(),
                entity.getResultObjectKey(),
                entity.getResultPreview(),
                entity.getFailureReason(),
                entity.getCreatedAt(),
                entity.getUpdatedAt()
        );
    }
}
