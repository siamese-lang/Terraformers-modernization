package com.terraformers.modernization.analysis;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

public record AnalysisJobRequest(
        @NotNull @Positive Long projectId,
        @NotNull @Positive Long sourceFileId,
        @Size(max = 128) String correlationId
) {
}
