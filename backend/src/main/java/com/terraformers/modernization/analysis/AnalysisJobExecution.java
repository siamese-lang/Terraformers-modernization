package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.ObjectWriteResult;

public record AnalysisJobExecution(
        AnalysisResult result,
        ObjectWriteResult writeResult
) {
}
