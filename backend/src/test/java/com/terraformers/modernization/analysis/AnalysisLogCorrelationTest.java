package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;

class AnalysisLogCorrelationTest {
    @Test
    void restoresMdcAfterAsynchronousAnalysisWork() {
        MDC.put("analysisJobId", "request-context");
        try (AnalysisLogCorrelation ignored = AnalysisLogCorrelation.forJob("job-42")) {
            assertThat(MDC.get("analysisJobId")).isEqualTo("job-42");
        }
        assertThat(MDC.get("analysisJobId")).isEqualTo("request-context");
        MDC.remove("analysisJobId");
    }
}
