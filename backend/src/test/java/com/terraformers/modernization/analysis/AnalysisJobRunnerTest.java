package com.terraformers.modernization.analysis;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.storage.ObjectWriteResult;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

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
        AnalysisJobRunner runner = new AnalysisJobRunner(orchestrator, stateService);

        runner.run("job-1");

        InOrder inOrder = inOrder(stateService, orchestrator);
        inOrder.verify(stateService).markRunning("job-1");
        inOrder.verify(orchestrator).executeProviderAndStoreDraft(running);
        inOrder.verify(stateService).markSucceeded("job-1", execution);
    }
}
