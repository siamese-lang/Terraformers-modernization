package com.terraformers.modernization.analysis;

import java.time.Instant;

public record ProgressEvent(
        String jobId,
        String projectId,
        String correlationId,
        AnalysisJobStatus status,
        String message,
        Instant occurredAt
) {
    public static ProgressEvent of(AnalysisJobEntity entity, AnalysisJobStatus status, String message) {
        return new ProgressEvent(
                entity.getId(),
                entity.getProjectId(),
                entity.getCorrelationId(),
                status,
                message,
                Instant.now()
        );
    }
}
