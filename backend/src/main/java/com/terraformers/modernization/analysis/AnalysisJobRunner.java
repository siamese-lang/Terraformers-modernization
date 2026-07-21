package com.terraformers.modernization.analysis;

import com.terraformers.modernization.analysis.bedrock.BedrockOutputTruncatedException;
import com.terraformers.modernization.analysis.bedrock.BedrockResponseFormatException;
import com.terraformers.modernization.analysis.bedrock.ArchitectureInputRejectedException;
import java.net.SocketTimeoutException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.exception.ApiCallAttemptTimeoutException;
import software.amazon.awssdk.core.exception.ApiCallTimeoutException;
import software.amazon.awssdk.core.exception.SdkClientException;

@Service
public class AnalysisJobRunner {

    static final String TIMEOUT_FAILURE_REASON = "AI 모델의 응답 시간이 초과되었습니다. 잠시 후 새 분석을 시작해 주세요.";
    static final String TRUNCATED_FAILURE_REASON = "아키텍처가 복잡해 AI 출력 한도를 초과했습니다. 핵심 구성만 남기거나 이미지를 여러 장으로 나누어 다시 시도해 주세요.";
    static final String FORMAT_FAILURE_REASON = "AI 응답 형식을 확인하지 못했습니다. 잠시 후 새 분석을 시작해 주세요.";
    static final String REJECTED_INPUT_FAILURE_REASON = "아키텍처 구성요소와 연결 관계를 확인할 수 없습니다. 시스템 구성도, 네트워크 구조도 또는 서비스 간 흐름이 표시된 이미지를 업로드해 주세요.";
    static final String GENERIC_FAILURE_REASON = "분석을 완료하지 못했습니다. 잠시 후 새 분석을 시작해 주세요.";
    private static final Logger log = LoggerFactory.getLogger(AnalysisJobRunner.class);

    private final AnalysisJobOrchestrator orchestrator;
    private final AnalysisJobStateService stateService;
    private final AnalysisObservability observability;

    public AnalysisJobRunner(AnalysisJobOrchestrator orchestrator, AnalysisJobStateService stateService, AnalysisObservability observability) {
        this.orchestrator = orchestrator;
        this.stateService = stateService;
        this.observability = observability;
    }

    public void run(String jobId) {
        AnalysisJobEntity runningJob = stateService.markRunning(jobId);
        try (AnalysisLogCorrelation ignored = AnalysisLogCorrelation.forJob(jobId)) {
            io.micrometer.core.instrument.Timer.Sample sample = observability.startAnalysis();
            observability.jobStarted();
            try {
                AnalysisJobExecution execution = orchestrator.executeProviderAndStoreDraft(runningJob);
                stateService.markSucceeded(jobId, execution);
                observability.jobSucceeded();
            } catch (RuntimeException exception) {
                observability.jobFailed(exception);
                log.error("Analysis job failed outcome=failed exceptionCategory={}", observability.category(exception));
                stateService.markFailed(jobId, safeFailureReason(exception));
            } finally {
                observability.stopAnalysis(sample);
            }
        }
    }

    public void markFailed(String jobId, String failureReason) {
        stateService.markFailed(jobId, failureReason);
    }

    private String safeFailureReason(RuntimeException exception) {
        Throwable current = exception;
        while (current != null) {
            if (current instanceof BedrockOutputTruncatedException) {
                return TRUNCATED_FAILURE_REASON;
            }
            if (current instanceof ArchitectureInputRejectedException) {
                return REJECTED_INPUT_FAILURE_REASON;
            }
            if (current instanceof BedrockResponseFormatException) {
                return FORMAT_FAILURE_REASON;
            }
            if (current instanceof SocketTimeoutException
                    || current instanceof ApiCallAttemptTimeoutException
                    || current instanceof ApiCallTimeoutException
                    || (current instanceof SdkClientException && hasReadTimeout(current))) {
                return TIMEOUT_FAILURE_REASON;
            }
            current = current.getCause();
        }
        return GENERIC_FAILURE_REASON;
    }

    private boolean hasReadTimeout(Throwable exception) {
        Throwable current = exception;
        while (current != null) {
            if (current.getMessage() != null && current.getMessage().toLowerCase().contains("read timed out")) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}
