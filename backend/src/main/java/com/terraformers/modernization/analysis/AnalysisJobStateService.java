package com.terraformers.modernization.analysis;

import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AnalysisJobStateService {

    private final AnalysisJobRepository repository;
    private final AnalysisJobOrchestrator orchestrator;

    public AnalysisJobStateService(AnalysisJobRepository repository, AnalysisJobOrchestrator orchestrator) {
        this.repository = repository;
        this.orchestrator = orchestrator;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public AnalysisJobEntity markRunning(String jobId) {
        AnalysisJobEntity entity = requireJob(jobId);
        orchestrator.markRunning(entity);
        return repository.save(entity);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markSucceeded(String jobId, AnalysisJobExecution execution) {
        AnalysisJobEntity entity = requireJob(jobId);
        orchestrator.markSucceeded(
                entity,
                execution.result(),
                execution.writeResult(),
                orchestrator.registerGeneratedTerraform(entity.getProjectId(), execution)
        );
        repository.save(entity);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markFailed(String jobId, String failureReason) {
        AnalysisJobEntity entity = requireJob(jobId);
        orchestrator.markFailed(entity, failureReason);
        repository.save(entity);
    }

    private AnalysisJobEntity requireJob(String jobId) {
        return repository.findById(jobId)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found: " + jobId));
    }
}
