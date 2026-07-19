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
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "bedrock-provider-enabled", havingValue = "true")
public class BedrockAnalysisProvider implements AnalysisProvider {

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
        this(
                bedrockRuntimeClient,
                objectReader,
                referenceRetriever,
                properties,
                promptBuilder,
                responseParser
        );
    }

    BedrockAnalysisProvider(
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

        String requestBody = promptBuilder.buildClaudeVisionRequest(
                source,
                references,
                properties.getBedrockMaxTokens()
        );

        InvokeModelResponse response = bedrockRuntimeClient.invokeModel(InvokeModelRequest.builder()
                .modelId(modelId)
                .contentType("application/json")
                .accept("application/json")
                .body(SdkBytes.fromUtf8String(requestBody))
                .build());

        ParsedBedrockAnalysis parsed = responseParser.parse(response.body().asUtf8String());

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

    private String requireModelId() {
        if (properties.getBedrockModelId() == null || properties.getBedrockModelId().isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set when Bedrock provider is enabled");
        }
        return properties.getBedrockModelId().strip();
    }
}
