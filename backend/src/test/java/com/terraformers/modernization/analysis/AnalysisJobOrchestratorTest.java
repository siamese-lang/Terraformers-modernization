package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.storage.ObjectWriteResult;
import com.terraformers.modernization.storage.StubObjectWriter;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class AnalysisJobOrchestratorTest {

    @Test
    void storesResultObjectKeyAndFileIdWhenAnalysisSucceeds() {
        AnalysisProvider provider = context -> new AnalysisResult(
                "test-provider",
                "resource \"aws_s3_bucket\" \"accepted\" { bucket_prefix = \"accepted-\" }",
                "test explanation",
                List.of("S3"),
                List.of("upload artifacts are stored in S3"),
                List.of(),
                List.of("reference-1")
        );
        CapturingProgressPublisher progressPublisher = new CapturingProgressPublisher();
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setResultBucketName("result-bucket");
        properties.setResultKeyPrefix("test-results");
        AnalysisResultStorage resultStorage = new AnalysisResultStorage(new StubObjectWriter(), properties);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ProjectFileEntity resultFile = mock(ProjectFileEntity.class);
        when(resultFile.getFileId()).thenReturn(301L);
        when(artifactService.registerGeneratedTerraform(anyLong(), anyString(), any(ObjectWriteResult.class)))
                .thenReturn(resultFile);
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(
                provider,
                progressPublisher,
                resultStorage,
                artifactService,
                new TerraformDraftValidator()
        );

        AnalysisJobEntity job = sampleEntity(101L);

        orchestrator.run(job);

        assertThat(job.getStatus()).isEqualTo(AnalysisJobStatus.SUCCEEDED);
        assertThat(job.getProvider()).isEqualTo("test-provider");
        assertThat(job.getResultFileId()).isEqualTo(301L);
        assertThat(job.getResultObjectKey()).startsWith("test-results/101/");
        assertThat(job.getResultObjectKey()).endsWith("/" + job.getId() + "/main.tf");
        assertThat(job.getResultPreview()).contains("resource \"aws_s3_bucket\"");
        verify(artifactService).registerGeneratedTerraform(
                101L,
                "resource \"aws_s3_bucket\" \"accepted\" { bucket_prefix = \"accepted-\" }",
                new ObjectWriteResult("result-bucket", job.getResultObjectKey(), "stub-etag")
        );
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
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(
                provider,
                progressPublisher,
                resultStorage,
                artifactService,
                new TerraformDraftValidator()
        );

        AnalysisJobEntity job = sampleEntity(102L);

        orchestrator.run(job);

        assertThat(job.getStatus()).isEqualTo(AnalysisJobStatus.FAILED);
        assertThat(job.getFailureReason()).contains("provider failure");
        assertThat(job.getResultFileId()).isNull();
        assertThat(job.getResultObjectKey()).isNull();
        verify(artifactService, never()).registerGeneratedTerraform(anyLong(), anyString(), any(ObjectWriteResult.class));
        assertThat(progressPublisher.statuses()).containsExactly(
                AnalysisJobStatus.RUNNING,
                AnalysisJobStatus.FAILED
        );
    }

    @Test
    void marksFailedAndDoesNotRegisterTerraformWhenProviderReturnsProviderOnlyCode() {
        AnalysisProvider provider = context -> new AnalysisResult(
                "test-provider",
                "provider \"aws\" { region = var.aws_region }",
                "provider only",
                List.of(),
                List.of(),
                List.of(),
                List.of()
        );
        CapturingProgressPublisher progressPublisher = new CapturingProgressPublisher();
        AnalysisResultStorage resultStorage = new AnalysisResultStorage(new StubObjectWriter(), new AnalysisRuntimeProperties());
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        AnalysisJobOrchestrator orchestrator = new AnalysisJobOrchestrator(
                provider,
                progressPublisher,
                resultStorage,
                artifactService,
                new TerraformDraftValidator()
        );

        AnalysisJobEntity job = sampleEntity(103L);

        orchestrator.run(job);

        assertThat(job.getStatus()).isEqualTo(AnalysisJobStatus.FAILED);
        assertThat(job.getFailureReason()).contains("resource or module");
        assertThat(job.getResultObjectKey()).isNull();
        verify(artifactService, never()).registerGeneratedTerraform(anyLong(), anyString(), any(ObjectWriteResult.class));
    }

    private AnalysisJobEntity sampleEntity(Long projectId) {
        AnalysisJobEntity job = new AnalysisJobEntity();
        job.setProjectId(projectId);
        job.setSourceFileId(201L);
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
