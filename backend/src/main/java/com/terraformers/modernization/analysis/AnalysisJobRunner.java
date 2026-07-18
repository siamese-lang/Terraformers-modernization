package com.terraformers.modernization.analysis;

import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AnalysisJobRunner {

    private final AnalysisJobRepository repository;
    private final AnalysisJobOrchestrator orchestrator;

    public AnalysisJobRunner(AnalysisJobRepository repository, AnalysisJobOrchestrator orchestrator) {
        this.repository = repository;
        this.orchestrator = orchestrator;
    }

    @Transactional
    public void run(String jobId) {
        AnalysisJobEntity entity = repository.findById(jobId)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found: " + jobId));
        orchestrator.run(entity);
        repository.save(entity);
    }
}
