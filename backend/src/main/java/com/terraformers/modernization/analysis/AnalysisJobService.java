package com.terraformers.modernization.analysis;

import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AnalysisJobService {

    private final AnalysisJobRepository repository;
    private final AnalysisRuntimeProperties properties;

    public AnalysisJobService(AnalysisJobRepository repository, AnalysisRuntimeProperties properties) {
        this.repository = repository;
        this.properties = properties;
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
        return AnalysisJobResponse.from(repository.save(entity));
    }

    @Transactional(readOnly = true)
    public AnalysisJobResponse get(String id) {
        return repository.findById(id)
                .map(AnalysisJobResponse::from)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found: " + id));
    }
}
