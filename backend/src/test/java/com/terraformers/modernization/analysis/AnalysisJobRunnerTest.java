package com.terraformers.modernization.analysis;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.verify;

import com.terraformers.modernization.storage.ObjectWriteResult;
import com.terraformers.modernization.analysis.bedrock.BedrockOutputTruncatedException;
import com.terraformers.modernization.analysis.bedrock.BedrockResponseFormatException;
import com.terraformers.modernization.analysis.bedrock.ArchitectureInputRejectedException;
import com.terraformers.modernization.analysis.bedrock.ArchitectureInputType;
import java.util.List;
import java.net.SocketTimeoutException;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import software.amazon.awssdk.core.exception.ApiCallAttemptTimeoutException;
import software.amazon.awssdk.core.exception.ApiCallTimeoutException;
import software.amazon.awssdk.core.exception.SdkClientException;

class AnalysisJobRunnerTest {

    @Test
    void committedPendingJobRunsOutsideCreateRequestAndReachesTerminalStatus() {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        AnalysisJobEntity running = new AnalysisJobEntity();
        running.setProjectId(42L);
        running.setSourceFileId(101L);
        running.setSourceBucket("source-bucket");
        running.setSourceKey("source/key.png");
        running.prePersist();
        AnalysisJobExecution execution = new AnalysisJobExecution(
                new AnalysisResult(
                        "stub",
                        "resource \"aws_s3_bucket\" \"accepted\" {}",
                        "summary",
                        List.of("S3"),
                        List.of(),
                        List.of(),
                        List.of()
                ),
                new ObjectWriteResult("result-bucket", "analysis/main.tf", "etag")
        );
        when(stateService.markRunning("job-1")).thenReturn(running);
        when(orchestrator.executeProviderAndStoreDraft(running)).thenReturn(execution);
        AnalysisJobRunner runner = new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(new SimpleMeterRegistry()));

        runner.run("job-1");

        InOrder inOrder = inOrder(stateService, orchestrator);
        inOrder.verify(stateService).markRunning("job-1");
        inOrder.verify(orchestrator).executeProviderAndStoreDraft(running);
        inOrder.verify(stateService).markSucceeded("job-1", execution);
    }

    @Test
    void readTimeoutMarksJobFailedWithSafeTimeoutMessage() {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        AnalysisJobEntity running = new AnalysisJobEntity();
        when(stateService.markRunning("job-1")).thenReturn(running);
        when(orchestrator.executeProviderAndStoreDraft(running))
                .thenThrow(software.amazon.awssdk.core.exception.SdkClientException.builder()
                        .message("Unable to execute HTTP request: Read timed out")
                        .cause(new SocketTimeoutException("Read timed out"))
                        .build());

        new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(new SimpleMeterRegistry())).run("job-1");

        verify(stateService).markFailed("job-1", AnalysisJobRunner.TIMEOUT_FAILURE_REASON);
    }

    @Test
    void generalFailureDoesNotExposeInternalExceptionDetails() {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        AnalysisJobEntity running = new AnalysisJobEntity();
        when(stateService.markRunning("job-1")).thenReturn(running);
        when(orchestrator.executeProviderAndStoreDraft(running))
                .thenThrow(new IllegalStateException("secret request body and stack details"));

        new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(new SimpleMeterRegistry())).run("job-1");

        verify(stateService).markFailed("job-1", AnalysisJobRunner.GENERIC_FAILURE_REASON);
    }

    @Test
    void apiCallAttemptTimeoutMarksJobFailedWithSafeTimeoutMessage() {
        assertFailureReason(ApiCallAttemptTimeoutException.builder().message("attempt timed out").build(),
                AnalysisJobRunner.TIMEOUT_FAILURE_REASON);
    }

    @Test
    void apiCallTimeoutMarksJobFailedWithSafeTimeoutMessage() {
        assertFailureReason(ApiCallTimeoutException.builder().message("call timed out").build(),
                AnalysisJobRunner.TIMEOUT_FAILURE_REASON);
    }

    @Test
    void generalSdkClientExceptionMarksJobFailedWithGenericMessage() {
        assertFailureReason(SdkClientException.builder().message("connection reset").build(),
                AnalysisJobRunner.GENERIC_FAILURE_REASON);
    }

    @Test
    void truncatedBedrockOutputMarksJobFailedWithSafeMessage() {
        assertFailureReason(new BedrockOutputTruncatedException(), AnalysisJobRunner.TRUNCATED_FAILURE_REASON);
    }

    @Test
    void invalidBedrockFormatMarksJobFailedWithSafeMessage() {
        assertFailureReason(new BedrockResponseFormatException("response body details"), AnalysisJobRunner.FORMAT_FAILURE_REASON);
    }

    @Test
    void rejectedArchitectureInputMarksJobFailedWithDedicatedMessage() {
        assertFailureReason(new ArchitectureInputRejectedException(ArchitectureInputType.NON_ARCHITECTURE_IMAGE, 0.98),
                AnalysisJobRunner.REJECTED_INPUT_FAILURE_REASON);
    }

    private void assertFailureReason(RuntimeException exception, String expectedReason) {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        AnalysisJobEntity running = new AnalysisJobEntity();
        when(stateService.markRunning("job-1")).thenReturn(running);
        when(orchestrator.executeProviderAndStoreDraft(running)).thenThrow(exception);

        new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(new SimpleMeterRegistry())).run("job-1");

        verify(stateService).markFailed("job-1", expectedReason);
    }
    @Test
    void markRunningFailureIsNotReclassifiedAsJobFailure() {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        org.mockito.Mockito.doThrow(new IllegalStateException("transition failed")).when(stateService).markRunning("job-transition");

        org.assertj.core.api.Assertions.assertThatThrownBy(() ->
                new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(new SimpleMeterRegistry())).run("job-transition"))
                .isInstanceOf(IllegalStateException.class);
        verify(stateService, org.mockito.Mockito.never()).markFailed(org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void orchestrationFailureAfterRunningRecordsStartedAndFailedMetrics() {
        AnalysisJobOrchestrator orchestrator = mock(AnalysisJobOrchestrator.class);
        AnalysisJobStateService stateService = mock(AnalysisJobStateService.class);
        AnalysisJobEntity running = new AnalysisJobEntity();
        when(stateService.markRunning("job-observed")).thenReturn(running);
        when(orchestrator.executeProviderAndStoreDraft(running)).thenThrow(new IllegalStateException("sensitive detail"));
        SimpleMeterRegistry registry = new SimpleMeterRegistry();

        new AnalysisJobRunner(orchestrator, stateService, new AnalysisObservability(registry)).run("job-observed");

        verify(stateService).markFailed(org.mockito.ArgumentMatchers.eq("job-observed"), org.mockito.ArgumentMatchers.anyString());
        org.assertj.core.api.Assertions.assertThat(registry.find("terraformers.analysis.jobs").tags("outcome", "started").counter().count()).isEqualTo(1);
        org.assertj.core.api.Assertions.assertThat(registry.find("terraformers.analysis.jobs").tags("outcome", "failed").counter().count()).isEqualTo(1);
    }

}
