package com.terraformers.modernization.analysis;

public enum AnalysisMode {
    INTEGRATED_JAVA,
    /** Historical database value only. New jobs must not select an external runtime. */
    EXTERNAL_PYTHON_LEGACY
}
