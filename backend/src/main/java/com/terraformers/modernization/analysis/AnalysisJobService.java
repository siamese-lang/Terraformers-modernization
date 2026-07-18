package com.terraformers.modernization.analysis;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import java.util.NoSuchElementException;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Service
public class AnalysisJobService {

    private final AnalysisJobRepository repository;
    private final AnalysisRuntimeProperties properties;
    private final AnalysisJobRunner jobRunner;
    private final Executor analysisJobExecutor;
    private final ProjectDomainService projectDomainService;
    private final ProjectFileRepository projectFileRepository;

    public AnalysisJobService(
            AnalysisJobRepository repository,
            AnalysisRuntimeProperties properties,
            AnalysisJobRunner jobRunner,
            @Qualifier("analysisJobExecutor") Executor analysisJobExecutor,
            ProjectDomainService projectDomainService,
            ProjectFileRepository projectFileRepository
    ) {
        this.repository = repository;
        this.properties = properties;
        this.jobRunner = jobRunner;
        this.analysisJobExecutor = analysisJobExecutor;
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
        schedule(saved.getId());
        return AnalysisJobResponse.from(saved);
    }

    private void schedule(String jobId) {
        Runnable task = () -> jobRunner.run(jobId);
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    executeOrMarkFailed(jobId, task);
                }
            });
            return;
        }
        executeOrMarkFailed(jobId, task);
    }

    private void executeOrMarkFailed(String jobId, Runnable task) {
        try {
            analysisJobExecutor.execute(task);
        } catch (RejectedExecutionException exception) {
            jobRunner.markFailed(jobId, "analysis job could not be scheduled because the executor rejected the task");
        }
    }

    @Transactional(readOnly = true)
    public AnalysisJobResponse get(String id, UserEntity requester) {
        AnalysisJobEntity entity = repository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found: " + id));
        projectDomainService.requireAccessibleProject(entity.getProjectId(), requester);
        return AnalysisJobResponse.from(entity);
    }
}
