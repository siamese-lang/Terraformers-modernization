package com.terraformers.modernization.analysis;

public interface AnalysisProvider {

    AnalysisResult analyze(AnalysisRequestContext context);
}
