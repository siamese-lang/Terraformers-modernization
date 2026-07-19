package com.terraformers.modernization.analysis;

import java.net.SocketTimeoutException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.exception.SdkClientException;

@Service
public class AnalysisJobRunner {

    static final String TIMEOUT_FAILURE_REASON = "AI 모델의 응답 시간이 초과되었습니다. 잠시 후 새 분석을 시작해 주세요.";
    static final String GENERIC_FAILURE_REASON = "분석을 완료하지 못했습니다. 잠시 후 새 분석을 시작해 주세요.";
    private static final Logger log = LoggerFactory.getLogger(AnalysisJobRunner.class);

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
            log.error("Analysis job failed: analysisJobId={}", jobId, exception);
            stateService.markFailed(jobId, safeFailureReason(exception));
        }
    }

    public void markFailed(String jobId, String failureReason) {
        stateService.markFailed(jobId, failureReason);
    }

    private String safeFailureReason(RuntimeException exception) {
        Throwable current = exception;
        while (current != null) {
            if (current instanceof SocketTimeoutException
                    || (current instanceof SdkClientException && isReadTimeout(current.getMessage()))) {
                return TIMEOUT_FAILURE_REASON;
            }
            current = current.getCause();
        }
        return GENERIC_FAILURE_REASON;
    }

    private boolean isReadTimeout(String message) {
        return message != null && message.toLowerCase().contains("read timed out");
    }
}
