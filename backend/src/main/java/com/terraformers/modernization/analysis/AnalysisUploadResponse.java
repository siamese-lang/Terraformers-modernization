package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.StoredUploadObject;
import java.time.Instant;

public record AnalysisUploadResponse(
        String uploadMode,
        String storageProvider,
        boolean binaryPersisted,
        String storageETag,
        String analysisJobId,
        Long projectId,
        Long sourceFileId,
        Long resultFileId,
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
        String analysisSummary,
        java.util.List<String> detectedComponents,
        java.util.List<String> detectedRelationships,
        java.util.List<String> warnings,
        String failureReason,
        Instant createdAt,
        Instant updatedAt
) {
    static AnalysisUploadResponse from(
            AnalysisJobResponse job,
            String originalFilename,
            String contentType,
            long size,
            StoredUploadObject storedUpload
    ) {
        return new AnalysisUploadResponse(
                "owned-project-analysis",
                storedUpload.provider(),
                storedUpload.binaryPersisted(),
                storedUpload.eTag(),
                job.id(),
                job.projectId(),
                job.sourceFileId(),
                job.resultFileId(),
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
                job.analysisSummary(),
                job.detectedComponents(),
                job.detectedRelationships(),
                job.warnings(),
                job.failureReason(),
                job.createdAt(),
                job.updatedAt()
        );
    }
}
