package com.terraformers.modernization.analysis;

import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AnalysisJobService {

    private final AnalysisJobRepository repository;
    private final AnalysisRuntimeProperties properties;
    private final AnalysisJobOrchestrator orchestrator;

    public AnalysisJobService(
            AnalysisJobRepository repository,
            AnalysisRuntimeProperties properties,
            AnalysisJobOrchestrator orchestrator
    ) {
        this.repository = repository;
        this.properties = properties;
        this.orchestrator = orchestrator;
    }

    @Transactional
    public AnalysisJobResponse create(AnalysisJobRequest request) {
        AnalysisJobEntity entity = new AnalysisJobEntity();
        entity.setProjectId(request.projectId());
        entity.setSourceBucket(request.sourceBucket());
        entity.setSourceKey(request.sourceKey());
        entity.setCorrelationId(request.correlationId());
        entity.setStatus(AnalysisJobStatus.PENDING);
        entity.setAnalysisMode(properties.getMode());

        AnalysisJobEntity saved = repository.save(entity);
        orchestrator.run(saved);
        return AnalysisJobResponse.from(saved);
    }

    @Transactional(readOnly = true)
    public AnalysisJobResponse get(String id) {
        return repository.findById(id)
                .map(AnalysisJobResponse::from)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found: " + id));
    }
}
