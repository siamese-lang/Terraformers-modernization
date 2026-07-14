package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.storage.StubObjectWriter;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class AnalysisJobOrchestratorTest {

    @Test
    void storesResultObjectKeyWhenAnalysisSucceeds() {
        AnalysisProvider provider = context -> new AnalysisResult(
                "test-provider",
                "provider \"aws\" {}",
                "test explanation",
                List.of("reference-1")
        );
        CapturingProgressPublisher progressPublisher = new CapturingProgressPublisher();
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setResultBucketName("result-bucket");
        properties.setResultKeyPrefix("test-results");
        AnalysisResultStorage resultStorage = new AnalysisResultStorage(new StubObjectWriter(), properties);
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(provider, progressPublisher, resultStorage);

        AnalysisJobEntity job = sampleEntity("project-1");

        orchestrator.run(job);

        assertThat(job.getStatus()).isEqualTo(AnalysisJobStatus.SUCCEEDED);
        assertThat(job.getProvider()).isEqualTo("test-provider");
        assertThat(job.getResultObjectKey()).startsWith("test-results/project-1/");
        assertThat(job.getResultObjectKey()).endsWith("/" + job.getId() + "/main.tf");
        assertThat(job.getResultPreview()).contains("provider \"aws\"");
        assertThat(progressPublisher.statuses()).containsExactly(
                AnalysisJobStatus.RUNNING,
                AnalysisJobStatus.SUCCEEDED
        );
    }

    @Test
    void marksFailedWhenAnalysisProviderFails() {
        AnalysisProvider provider = context -> {
            throw new IllegalStateException("provider failure");
        };
        CapturingProgressPublisher progressPublisher = new CapturingProgressPublisher();
        AnalysisResultStorage resultStorage = new AnalysisResultStorage(new StubObjectWriter(), new AnalysisRuntimeProperties());
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(provider, progressPublisher, resultStorage);

        AnalysisJobEntity job = sampleEntity("project-2");

        orchestrator.run(job);

        assertThat(job.getStatus()).isEqualTo(AnalysisJobStatus.FAILED);
        assertThat(job.getFailureReason()).contains("provider failure");
        assertThat(job.getResultObjectKey()).isNull();
        assertThat(progressPublisher.statuses()).containsExactly(
                AnalysisJobStatus.RUNNING,
                AnalysisJobStatus.FAILED
        );
    }

    private AnalysisJobEntity sampleEntity(String projectId) {
        AnalysisJobEntity job = new AnalysisJobEntity();
        job.setProjectId(projectId);
        job.setSourceBucket("source-bucket");
        job.setSourceKey("uploads/diagram.png");
        job.setCorrelationId("corr-1");
        job.setAnalysisMode(AnalysisMode.INTEGRATED_JAVA);
        job.prePersist();
        return job;
    }

    private static class CapturingProgressPublisher implements ProgressPublisher {
        private final List<ProgressEvent> events = new ArrayList<>();

        @Override
        public void publish(ProgressEvent event) {
            events.add(event);
        }

        List<AnalysisJobStatus> statuses() {
            return events.stream().map(ProgressEvent::status).toList();
        }
    }
}
