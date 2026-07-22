package com.terraformers.modernization.analysis;

import org.slf4j.MDC;

final class AnalysisLogCorrelation implements AutoCloseable {
    private final String previous;

    private AnalysisLogCorrelation(String previous) { this.previous = previous; }

    static AnalysisLogCorrelation forJob(String analysisJobId) {
        String previous = MDC.get("analysisJobId");
        MDC.put("analysisJobId", analysisJobId);
        return new AnalysisLogCorrelation(previous);
    }

    @Override
    public void close() {
        if (previous == null) MDC.remove("analysisJobId"); else MDC.put("analysisJobId", previous);
    }
}
