package com.terraformers.modernization.analysis.bedrock;

import com.terraformers.modernization.analysis.AnalysisProvider;
import com.terraformers.modernization.analysis.AnalysisRequestContext;
import com.terraformers.modernization.analysis.AnalysisResult;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "bedrock-provider-enabled", havingValue = "true")
public class BedrockAnalysisProvider implements AnalysisProvider {

    private static final Logger log = LoggerFactory.getLogger(BedrockAnalysisProvider.class);

    private final BedrockRuntimeClient bedrockRuntimeClient;
    private final ObjectReader objectReader;
    private final ReferenceRetriever referenceRetriever;
    private final AnalysisRuntimeProperties properties;
    private final BedrockPromptBuilder promptBuilder;
    private final BedrockResponseParser responseParser;

    public BedrockAnalysisProvider(
            BedrockRuntimeClient bedrockRuntimeClient,
            ObjectReader objectReader,
            ReferenceRetriever referenceRetriever,
            AnalysisRuntimeProperties properties,
            BedrockPromptBuilder promptBuilder,
            BedrockResponseParser responseParser
    ) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectReader = objectReader;
        this.referenceRetriever = referenceRetriever;
        this.properties = properties;
        this.promptBuilder = promptBuilder;
        this.responseParser = responseParser;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        String modelId = requireModelId();

        ObjectContent source = objectReader.readContent(new ObjectReference(
                context.sourceBucket(),
                context.sourceKey()
        ));

        List<ReferenceDocument> references = referenceRetriever.retrieve(ReferenceQuery.fromObject(
                context.projectId(),
                source.metadata().bucket(),
                source.metadata().key(),
                source.metadata().contentType()
        ));

        ParsedBedrockAnalysis parsed;
        try {
            parsed = invokeAndParse(context, source, references, modelId, 1, BedrockPromptMode.STANDARD);
        } catch (BedrockOutputTruncatedException exception) {
            parsed = invokeAndParse(context, source, references, modelId, 2, BedrockPromptMode.COMPACT);
        }

        return new AnalysisResult(
                "bedrock:" + modelId,
                parsed.terraformCode(),
                parsed.summary(),
                parsed.components(),
                parsed.relationships(),
                parsed.warnings(),
                references.stream().map(ReferenceDocument::id).toList()
        );
    }

    private ParsedBedrockAnalysis invokeAndParse(
            AnalysisRequestContext context,
            ObjectContent source,
            List<ReferenceDocument> references,
            String modelId,
            int attempt,
            BedrockPromptMode promptMode
    ) {
        long startedAt = System.nanoTime();
        String requestBody = promptBuilder.buildClaudeVisionRequest(
                source, references, properties.getBedrockMaxTokens(), promptMode);
        try {
            InvokeModelResponse response = bedrockRuntimeClient.invokeModel(InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(SdkBytes.fromUtf8String(requestBody))
                    .build());
            ParsedBedrockAnalysis parsed = responseParser.parse(response.body().asUtf8String());
            logCall(context, modelId, attempt, promptMode, parsed.stopReason(), parsed.outputTokens(), false, startedAt);
            return parsed;
        } catch (BedrockOutputTruncatedException exception) {
            logCall(context, modelId, attempt, promptMode, exception.getStopReason(), exception.getOutputTokens(), true, startedAt);
            throw exception;
        } catch (ArchitectureInputRejectedException exception) {
            logRejectedCall(context, modelId, attempt, promptMode, exception, startedAt);
            throw exception;
        } catch (RuntimeException exception) {
            logFailedCall(context, modelId, attempt, promptMode, exception, startedAt);
            throw exception;
        }
    }

    private void logRejectedCall(AnalysisRequestContext context, String modelId, int attempt, BedrockPromptMode promptMode,
            ArchitectureInputRejectedException exception, long startedAt) {
        long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;
        log.warn("Bedrock analysis call rejected: analysisJobId={} projectId={} modelId={} attempt={} promptMode={} inputType={} classificationConfidence={} maxTokens={} outcome={} errorType={} elapsedMs={}",
                context.jobId(), context.projectId(), modelId, attempt, promptMode, exception.getInputType(),
                exception.getClassificationConfidence(), properties.getBedrockMaxTokens(), "REJECTED",
                exception.getClass().getSimpleName(), elapsedMs);
    }

    private void logCall(
            AnalysisRequestContext context,
            String modelId,
            int attempt,
            BedrockPromptMode promptMode,
            String stopReason,
            Integer outputTokens,
            boolean truncated,
            long startedAt
    ) {
        long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;
        if (truncated) {
            log.warn("Bedrock analysis call completed with truncation{}: analysisJobId={} projectId={} modelId={} attempt={} promptMode={} stopReason={} outputTokens={} maxTokens={} truncated={} elapsedMs={}",
                    attempt == 1 ? "; compact retry will start" : "",
                    context.jobId(), context.projectId(), modelId, attempt, promptMode, stopReason, outputTokens,
                    properties.getBedrockMaxTokens(), true, elapsedMs);
            return;
        }
        log.info("Bedrock analysis call completed: analysisJobId={} projectId={} modelId={} attempt={} promptMode={} stopReason={} outputTokens={} maxTokens={} truncated={} elapsedMs={}",
                context.jobId(), context.projectId(), modelId, attempt, promptMode, stopReason, outputTokens,
                properties.getBedrockMaxTokens(), false, elapsedMs);
    }

    private void logFailedCall(
            AnalysisRequestContext context,
            String modelId,
            int attempt,
            BedrockPromptMode promptMode,
            RuntimeException exception,
            long startedAt
    ) {
        long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;
        log.warn("Bedrock analysis call failed: analysisJobId={} projectId={} modelId={} attempt={} promptMode={} stopReason={} outputTokens={} maxTokens={} truncated={} outcome={} errorType={} elapsedMs={}",
                context.jobId(), context.projectId(), modelId, attempt, promptMode, "unknown", null,
                properties.getBedrockMaxTokens(), false, "FAILED", exception.getClass().getSimpleName(), elapsedMs);
    }

    private String requireModelId() {
        if (properties.getBedrockModelId() == null || properties.getBedrockModelId().isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set when Bedrock provider is enabled");
        }
        return properties.getBedrockModelId().strip();
    }
}
