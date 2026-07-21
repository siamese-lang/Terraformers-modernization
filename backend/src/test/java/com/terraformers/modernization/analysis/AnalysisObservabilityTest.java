package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

class AnalysisObservabilityTest {
    @Test
    void recordsOnlyBoundedAnalysisOutcomesAndCategories() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        AnalysisObservability observability = new AnalysisObservability(registry);

        observability.jobStarted();
        observability.jobSucceeded();
        observability.jobFailed(new IllegalStateException("sensitive detail must not be a tag"));

        assertThat(registry.find("terraformers.analysis.jobs").tags("outcome", "started").counter().count()).isEqualTo(1);
        assertThat(registry.find("terraformers.analysis.jobs").tags("outcome", "succeeded").counter().count()).isEqualTo(1);
        assertThat(registry.find("terraformers.analysis.jobs").tags("outcome", "failed", "exception_category", "other").counter().count()).isEqualTo(1);
    }
}
