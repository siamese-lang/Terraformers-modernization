package com.terraformers.modernization.analysis;

public record AnalysisRequestContext(
        String jobId,
        String projectId,
        String sourceBucket,
        String sourceKey,
        String correlationId,
        AnalysisMode analysisMode
) {
}
