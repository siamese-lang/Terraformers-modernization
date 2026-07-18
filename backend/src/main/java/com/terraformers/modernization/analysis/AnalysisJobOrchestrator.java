package com.terraformers.modernization.analysis;

import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.storage.ObjectWriteResult;
import org.springframework.stereotype.Service;

@Service
public class AnalysisJobOrchestrator {

    private final AnalysisProvider analysisProvider;
    private final ProgressPublisher progressPublisher;
    private final AnalysisResultStorage resultStorage;
    private final ProjectArtifactService projectArtifactService;
    private final TerraformDraftValidator terraformDraftValidator;

    public AnalysisJobOrchestrator(
            AnalysisProvider analysisProvider,
            ProgressPublisher progressPublisher,
            AnalysisResultStorage resultStorage,
            ProjectArtifactService projectArtifactService,
            TerraformDraftValidator terraformDraftValidator
    ) {
        this.analysisProvider = analysisProvider;
        this.progressPublisher = progressPublisher;
        this.resultStorage = resultStorage;
        this.projectArtifactService = projectArtifactService;
        this.terraformDraftValidator = terraformDraftValidator;
    }

    public void run(AnalysisJobEntity entity) {
        try {
            markRunning(entity);
            AnalysisJobExecution execution = executeProviderAndStoreDraft(entity);
            ProjectFileEntity resultFile = registerGeneratedTerraform(entity.getProjectId(), execution);
            markSucceeded(entity, execution.result(), execution.writeResult(), resultFile);
        } catch (RuntimeException exception) {
            markFailed(entity, exception);
        }
    }

    public AnalysisJobExecution executeProviderAndStoreDraft(AnalysisJobEntity entity) {
        AnalysisResult result = analysisProvider.analyze(toContext(entity));
        TerraformDraftValidation validation = terraformDraftValidator.validate(result.terraformCode());
        if (!validation.valid()) {
            throw new IllegalStateException(validation.reason());
        }
        AnalysisResult sanitizedResult = result.withTerraformCode(validation.sanitizedContent());
        ObjectWriteResult writeResult = resultStorage.storeTerraformDraft(entity, sanitizedResult);
        return new AnalysisJobExecution(sanitizedResult, writeResult);
    }

    public ProjectFileEntity registerGeneratedTerraform(Long projectId, AnalysisJobExecution execution) {
        return projectArtifactService.registerGeneratedTerraform(
                projectId,
                execution.result().terraformCode(),
                execution.writeResult()
        );
    }

    public void markRunning(AnalysisJobEntity entity) {
        entity.setStatus(AnalysisJobStatus.RUNNING);
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.RUNNING, "analysis job started"));
    }

    public void markSucceeded(
            AnalysisJobEntity entity,
            AnalysisResult result,
            ObjectWriteResult writeResult,
            ProjectFileEntity resultFile
    ) {
        entity.setStatus(AnalysisJobStatus.SUCCEEDED);
        entity.setProvider(result.provider());
        entity.setResultFileId(resultFile.getFileId());
        entity.setResultObjectKey(writeResult.key());
        entity.setResultPreview(result.preview());
        entity.setAnalysisSummary(result.explanation());
        entity.setDetectedComponents(String.join("\n", result.components() == null ? java.util.List.of() : result.components()));
        entity.setDetectedRelationships(String.join("\n", result.relationships() == null ? java.util.List.of() : result.relationships()));
        entity.setAnalysisWarnings(String.join("\n", result.warnings() == null ? java.util.List.of() : result.warnings()));
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.SUCCEEDED, "analysis job completed"));
    }

    public void markFailed(AnalysisJobEntity entity, RuntimeException exception) {
        markFailed(entity, exception.getMessage());
    }

    public void markFailed(AnalysisJobEntity entity, String failureReason) {
        entity.setStatus(AnalysisJobStatus.FAILED);
        entity.setFailureReason(safeFailureReason(failureReason));
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.FAILED, "analysis job failed"));
    }

    private String safeFailureReason(String failureReason) {
        String reason = failureReason == null || failureReason.isBlank()
                ? "analysis job failed"
                : failureReason.strip();
        return reason.length() <= 2000 ? reason : reason.substring(0, 2000);
    }

    private AnalysisRequestContext toContext(AnalysisJobEntity entity) {
        return new AnalysisRequestContext(
                entity.getId(),
                String.valueOf(entity.getProjectId()),
                entity.getSourceBucket(),
                entity.getSourceKey(),
                entity.getCorrelationId(),
                entity.getAnalysisMode()
        );
    }
}
