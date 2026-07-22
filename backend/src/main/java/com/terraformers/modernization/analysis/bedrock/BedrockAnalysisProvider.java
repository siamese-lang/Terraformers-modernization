package com.terraformers.modernization.analysis.bedrock;

import com.terraformers.modernization.analysis.AnalysisProvider;
import com.terraformers.modernization.analysis.AnalysisRequestContext;
import com.terraformers.modernization.analysis.AnalysisResult;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.analysis.AnalysisObservability;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.reference.ArchitectureRetrievalFacts;
import com.terraformers.modernization.reference.BedrockArchitectureFactsExtractor;
import com.terraformers.modernization.reference.RetrievalMode;
import com.terraformers.modernization.reference.RetrievalQueryTextBuilder;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Autowired;
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
    private final BedrockArchitectureFactsExtractor factsExtractor;
    private final RetrievalQueryTextBuilder queryTextBuilder;
    private final AnalysisObservability observability;

    @Autowired
    public BedrockAnalysisProvider(
            BedrockRuntimeClient bedrockRuntimeClient,
            ObjectReader objectReader,
            ReferenceRetriever referenceRetriever,
            AnalysisRuntimeProperties properties,
            BedrockPromptBuilder promptBuilder,
            BedrockResponseParser responseParser, BedrockArchitectureFactsExtractor factsExtractor,
            RetrievalQueryTextBuilder queryTextBuilder, AnalysisObservability observability
    ) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectReader = objectReader;
        this.referenceRetriever = referenceRetriever;
        this.properties = properties;
        this.promptBuilder = promptBuilder;
        this.responseParser = responseParser;
        this.factsExtractor = factsExtractor;
        this.queryTextBuilder = queryTextBuilder;
        this.observability = observability;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        long analysisStartedAt = System.nanoTime();
        String modelId = requireModelId();

        ObjectContent source = objectReader.readContent(new ObjectReference(
                context.sourceBucket(),
                context.sourceKey()
        ));

        List<ReferenceDocument> references = retrieveReferences(context, source);

        ParsedBedrockAnalysis parsed;
        try {
            parsed = invokeAndParse(context, source, references, modelId, 1, BedrockPromptMode.STANDARD);
        } catch (BedrockOutputTruncatedException exception) {
            parsed = invokeAndParse(context, source, references, modelId, 2, BedrockPromptMode.COMPACT);
        }

        AnalysisResult result = new AnalysisResult(
                "bedrock:" + modelId,
                parsed.terraformCode(),
                parsed.summary(),
                parsed.components(),
                parsed.relationships(),
                parsed.warnings(),
                references.stream().map(ReferenceDocument::id).toList()
        );
        log.info(
                "analysis pipeline outcome=success corpusVersion={} providerVersion={} referenceCount={} elapsedMs={}",
                properties.getCorpusVersion(),
                properties.getProviderVersion(),
                references.size(),
                (System.nanoTime() - analysisStartedAt) / 1_000_000
        );
        return result;
    }

    private List<ReferenceDocument> retrieveReferences(AnalysisRequestContext context, ObjectContent source) {
        RetrievalMode mode = properties.getRetrievalMode();
        if (mode == null) throw new IllegalStateException("terraformers.analysis.retrieval-mode must be set");
        if (mode == RetrievalMode.DISABLED) return List.of();
        long started = System.nanoTime();
        try {
            if (factsExtractor == null || queryTextBuilder == null) {
                throw new IllegalStateException("architecture retrieval facts stage is not configured");
            }
            long factsStartedAt = System.nanoTime();
            ArchitectureRetrievalFacts facts = factsExtractor.extract(source);
            long factsElapsedMs = (System.nanoTime() - factsStartedAt) / 1_000_000;
            long searchStartedAt = System.nanoTime();
            List<ReferenceDocument> references = observability.recordAoss(() -> referenceRetriever.retrieve(
                    new ReferenceQuery(queryTextBuilder.build(facts), properties.getOpensearchTopK())
            ));
            observability.retrievedHits(references.size());
            long searchElapsedMs = (System.nanoTime() - searchStartedAt) / 1_000_000;
            log.info(
                    "reference retrieval outcome=success mode={} corpusVersion={} providerVersion={} topK={} referenceCount={} factsElapsedMs={} searchElapsedMs={} elapsedMs={}",
                    mode, properties.getCorpusVersion(), properties.getProviderVersion(), properties.getOpensearchTopK(),
                    references.size(), factsElapsedMs, searchElapsedMs, (System.nanoTime() - started) / 1_000_000
            );
            return references;
        } catch (RuntimeException exception) {
            log.warn("reference retrieval outcome=failure mode={} corpusVersion={} providerVersion={} topK={} errorClass={} elapsedMs={}",
                    mode, properties.getCorpusVersion(), properties.getProviderVersion(), properties.getOpensearchTopK(),
                    exception.getClass().getSimpleName(), (System.nanoTime() - started) / 1_000_000);
            if (mode == RetrievalMode.REQUIRED) throw exception;
            return List.of();
        }
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
            InvokeModelResponse response = observability.recordBedrock(() -> bedrockRuntimeClient.invokeModel(InvokeModelRequest.builder()
                    .modelId(modelId)
                    .contentType("application/json")
                    .accept("application/json")
                    .body(SdkBytes.fromUtf8String(requestBody))
                    .build()));
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
        log.warn("Bedrock analysis call rejected outcome=REJECTED errorType={} elapsedMs={}", exception.getClass().getSimpleName(), elapsedMs);
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
            log.warn("Bedrock analysis call completed with truncation retry={} elapsedMs={}", attempt == 1, elapsedMs);
            return;
        }
        log.info("Bedrock analysis call completed outcome=SUCCESS elapsedMs={}", elapsedMs);
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
        log.warn("Bedrock analysis call failed outcome=FAILED errorType={} elapsedMs={}", exception.getClass().getSimpleName(), elapsedMs);
    }

    private String requireModelId() {
        if (properties.getBedrockModelId() == null || properties.getBedrockModelId().isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set when Bedrock provider is enabled");
        }
        return properties.getBedrockModelId().strip();
    }
}
