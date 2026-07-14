package com.terraformers.modernization.analysis;

import java.time.Instant;

public record AnalysisUploadResponse(
        String uploadMode,
        String analysisJobId,
        String projectId,
        String sourceBucket,
        String sourceKey,
        String originalFilename,
        String contentType,
        long size,
        AnalysisJobStatus status,
        AnalysisMode analysisMode,
        String provider,
        String resultObjectKey,
        String resultPreview,
        String failureReason,
        Instant createdAt,
        Instant updatedAt
) {
    static AnalysisUploadResponse from(
            AnalysisJobResponse job,
            String originalFilename,
            String contentType,
            long size
    ) {
        return new AnalysisUploadResponse(
                "analysis-job-compatibility",
                job.id(),
                job.projectId(),
                job.sourceBucket(),
                job.sourceKey(),
                originalFilename,
                contentType,
                size,
                job.status(),
                job.analysisMode(),
                job.provider(),
                job.resultObjectKey(),
                job.resultPreview(),
                job.failureReason(),
                job.createdAt(),
                job.updatedAt()
        );
    }
}
