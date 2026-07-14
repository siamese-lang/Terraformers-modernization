package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class AnalysisJobOrchestratorTest {

    @Test
    void runMarksJobSucceededWhenProviderReturnsResult() {
        AnalysisJobEntity entity = sampleEntity();
        List<ProgressEvent> events = new ArrayList<>();

        AnalysisProvider provider = context -> new AnalysisResult(
                "test-provider",
                "provider \"aws\" {}",
                "ok",
                List.of("reference")
        );
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(provider, events::add);

        orchestrator.run(entity);

        assertThat(entity.getStatus()).isEqualTo(AnalysisJobStatus.SUCCEEDED);
        assertThat(entity.getProvider()).isEqualTo("test-provider");
        assertThat(entity.getResultPreview()).contains("provider");
        assertThat(events).extracting(ProgressEvent::status)
                .containsExactly(AnalysisJobStatus.RUNNING, AnalysisJobStatus.SUCCEEDED);
    }

    @Test
    void runMarksJobFailedWhenProviderThrowsException() {
        AnalysisJobEntity entity = sampleEntity();
        List<ProgressEvent> events = new ArrayList<>();

        AnalysisProvider provider = context -> {
            throw new IllegalStateException("bedrock timeout");
        };
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(provider, events::add);

        orchestrator.run(entity);

        assertThat(entity.getStatus()).isEqualTo(AnalysisJobStatus.FAILED);
        assertThat(entity.getFailureReason()).isEqualTo("bedrock timeout");
        assertThat(events).extracting(ProgressEvent::status)
                .containsExactly(AnalysisJobStatus.RUNNING, AnalysisJobStatus.FAILED);
    }

    private AnalysisJobEntity sampleEntity() {
        AnalysisJobEntity entity = new AnalysisJobEntity();
        entity.setProjectId("project-1");
        entity.setSourceBucket("terraformers-sample-bucket");
        entity.setSourceKey("uploads/diagram.png");
        entity.setCorrelationId("corr-1");
        entity.setAnalysisMode(AnalysisMode.INTEGRATED_JAVA);
        entity.prePersist();
        return entity;
    }
}
