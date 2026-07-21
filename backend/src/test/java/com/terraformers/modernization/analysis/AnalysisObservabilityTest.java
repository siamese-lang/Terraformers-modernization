package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.Tag;
import io.micrometer.prometheusmetrics.PrometheusConfig;
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry;
import org.junit.jupiter.api.Test;

class AnalysisObservabilityTest {
    @Test
    void publishesFixedPrometheusMeterIdentitiesWithoutSensitiveLabels() {
        PrometheusMeterRegistry registry = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);
        AnalysisObservability observability = new AnalysisObservability(registry);

        observability.jobStarted();
        observability.jobSucceeded();
        observability.jobFailed(new IllegalStateException("secret raw message"));
        observability.recordBedrock(() -> "ok");
        try {
            observability.recordBedrock(() -> {
                throw new IllegalStateException("secret raw message");
            });
        } catch (IllegalStateException ignored) {
        }
        observability.recordAoss(() -> "ok");
        try {
            observability.recordAoss(() -> {
                throw new IllegalStateException("secret raw message");
            });
        } catch (IllegalStateException ignored) {
        }
        observability.retrievedHits(3);

        String scrape = registry.scrape();
        assertThat(scrape).contains(
                "terraformers_analysis_jobs",
                "terraformers_bedrock_invocations",
                "terraformers_aoss_retrievals",
                "terraformers_aoss_retrieved_hits"
        );
        assertThat(scrape).contains("category=\"other\"").doesNotContain("secret raw message");
        assertThat(registry.find("terraformers.analysis.jobs").meters()).allSatisfy(meter ->
                assertThat(meter.getId().getTags())
                        .extracting(Tag::getKey)
                        .containsExactly("outcome")
        );
    }
}
