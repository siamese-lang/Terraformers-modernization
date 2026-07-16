package com.terraformers.modernization.analysis;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AnalysisJobService {

    private final AnalysisJobRepository repository;
    private final AnalysisRuntimeProperties properties;
    private final AnalysisJobOrchestrator orchestrator;
    private final ProjectDomainService projectDomainService;
    private final ProjectFileRepository projectFileRepository;

    public AnalysisJobService(
            AnalysisJobRepository repository,
            AnalysisRuntimeProperties properties,
            AnalysisJobOrchestrator orchestrator,
            ProjectDomainService projectDomainService,
            ProjectFileRepository projectFileRepository
    ) {
        this.repository = repository;
        this.properties = properties;
        this.orchestrator = orchestrator;
        this.projectDomainService = projectDomainService;
        this.projectFileRepository = projectFileRepository;
    }

    @Transactional
    public AnalysisJobResponse create(AnalysisJobRequest request, UserEntity requester) {
        OwnedProjectEntity project = projectDomainService.requireModifiableProject(request.projectId(), requester);
        ProjectFileEntity sourceFile = projectFileRepository.findById(request.sourceFileId())
                .filter(file -> file.getDeletedAt() == null)
                .orElseThrow(() -> new NoSuchElementException("source file not found: " + request.sourceFileId()));

        if (sourceFile.getProject() == null
                || !project.getProjectId().equals(sourceFile.getProject().getProjectId())) {
            throw new IllegalArgumentException("source file does not belong to project: " + request.projectId());
        }
        if (sourceFile.getS3Bucket() == null || sourceFile.getS3Bucket().isBlank()
                || sourceFile.getS3Key() == null || sourceFile.getS3Key().isBlank()) {
            throw new IllegalArgumentException("source file is missing object storage metadata");
        }

        AnalysisJobEntity entity = new AnalysisJobEntity();
        entity.setProjectId(project.getProjectId());
        entity.setSourceFileId(sourceFile.getFileId());
        entity.setSourceBucket(sourceFile.getS3Bucket());
        entity.setSourceKey(sourceFile.getS3Key());
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
