package com.terraformers.modernization.analysis;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record AnalysisJobRequest(
        @NotBlank @Size(max = 64) String projectId,
        @NotBlank @Size(max = 255) String sourceBucket,
        @NotBlank @Size(max = 1024) String sourceKey,
        @Size(max = 128) String correlationId
) {
}
