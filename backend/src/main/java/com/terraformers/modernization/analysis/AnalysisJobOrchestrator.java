package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.ObjectWriteResult;
import org.springframework.stereotype.Service;

@Service
public class AnalysisJobOrchestrator {

    private final AnalysisProvider analysisProvider;
    private final ProgressPublisher progressPublisher;
    private final AnalysisResultStorage resultStorage;

    public AnalysisJobOrchestrator(
            AnalysisProvider analysisProvider,
            ProgressPublisher progressPublisher,
            AnalysisResultStorage resultStorage
    ) {
        this.analysisProvider = analysisProvider;
        this.progressPublisher = progressPublisher;
        this.resultStorage = resultStorage;
    }

    public void run(AnalysisJobEntity entity) {
        try {
            markRunning(entity);
            AnalysisResult result = analysisProvider.analyze(toContext(entity));
            ObjectWriteResult writeResult = resultStorage.storeTerraformDraft(entity, result);
            markSucceeded(entity, result, writeResult);
        } catch (RuntimeException exception) {
            markFailed(entity, exception);
        }
    }

    private void markRunning(AnalysisJobEntity entity) {
        entity.setStatus(AnalysisJobStatus.RUNNING);
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.RUNNING, "analysis job started"));
    }

    private void markSucceeded(AnalysisJobEntity entity, AnalysisResult result, ObjectWriteResult writeResult) {
        entity.setStatus(AnalysisJobStatus.SUCCEEDED);
        entity.setProvider(result.provider());
        entity.setResultObjectKey(writeResult.key());
        entity.setResultPreview(result.preview());
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.SUCCEEDED, "analysis job completed"));
    }

    private void markFailed(AnalysisJobEntity entity, RuntimeException exception) {
        entity.setStatus(AnalysisJobStatus.FAILED);
        entity.setFailureReason(exception.getMessage());
        progressPublisher.publish(ProgressEvent.of(entity, AnalysisJobStatus.FAILED, "analysis job failed"));
    }

    private AnalysisRequestContext toContext(AnalysisJobEntity entity) {
        return new AnalysisRequestContext(
                entity.getId(),
                entity.getProjectId(),
                entity.getSourceBucket(),
                entity.getSourceKey(),
                entity.getCorrelationId(),
                entity.getAnalysisMode()
        );
    }
}
