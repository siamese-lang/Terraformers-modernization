package com.terraformers.modernization.analysis;

import org.springframework.stereotype.Service;

@Service
public class AnalysisJobRunner {

    private final AnalysisJobOrchestrator orchestrator;
    private final AnalysisJobStateService stateService;

    public AnalysisJobRunner(AnalysisJobOrchestrator orchestrator, AnalysisJobStateService stateService) {
        this.orchestrator = orchestrator;
        this.stateService = stateService;
    }

    public void run(String jobId) {
        AnalysisJobEntity runningJob = stateService.markRunning(jobId);
        try {
            AnalysisJobExecution execution = orchestrator.executeProviderAndStoreDraft(runningJob);
            stateService.markSucceeded(jobId, execution);
        } catch (RuntimeException exception) {
            stateService.markFailed(jobId, exception.getMessage());
        }
    }

    public void markFailed(String jobId, String failureReason) {
        stateService.markFailed(jobId, failureReason);
    }
}
