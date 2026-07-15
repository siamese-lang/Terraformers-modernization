package com.terraformers.modernization.analysis;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.storage.ObjectMetadata;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Component
@Primary
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "bedrock-provider-enabled", havingValue = "true")
public class BedrockRuntimeAnalysisProvider implements AnalysisProvider {

    private static final String ANTHROPIC_VERSION = "bedrock-2023-05-31";
    private static final int MAX_REFERENCE_CONTENT_LENGTH = 500;

    private final BedrockRuntimeClient bedrockRuntimeClient;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;
    private final ObjectReader objectReader;
    private final ReferenceRetriever referenceRetriever;

    @Autowired
    public BedrockRuntimeAnalysisProvider(
            ObjectMapper objectMapper,
            AnalysisRuntimeProperties properties,
            ObjectReader objectReader,
            ReferenceRetriever referenceRetriever
    ) {
        this(BedrockRuntimeClient.builder().build(), objectMapper, properties, objectReader, referenceRetriever);
    }

    BedrockRuntimeAnalysisProvider(
            BedrockRuntimeClient bedrockRuntimeClient,
            ObjectMapper objectMapper,
            AnalysisRuntimeProperties properties,
            ObjectReader objectReader,
            ReferenceRetriever referenceRetriever
    ) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectMapper = objectMapper;
        this.properties = properties;
        this.objectReader = objectReader;
        this.referenceRetriever = referenceRetriever;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        String modelId = requireModelId();
        ObjectMetadata metadata = objectReader.readMetadata(new ObjectReference(
                context.sourceBucket(),
                context.sourceKey()
        ));
        List<ReferenceDocument> references = referenceRetriever.retrieve(ReferenceQuery.fromObject(
                context.projectId(),
                metadata.bucket(),
                metadata.key(),
                metadata.contentType()
        ));
        String prompt = buildPrompt(context, metadata, references);
        String requestBody = toAnthropicMessagesRequest(prompt);

        InvokeModelResponse response = bedrockRuntimeClient.invokeModel(InvokeModelRequest.builder()
                .modelId(modelId)
                .contentType("application/json")
                .accept("application/json")
                .body(SdkBytes.fromUtf8String(requestBody))
                .build());

        String terraformCode = extractText(response.body().asUtf8String());
        return new AnalysisResult(
                "bedrock-runtime",
                terraformCode,
                "Generated through Bedrock Runtime model " + modelId
                        + " using stored source metadata and " + references.size() + " retrieved reference document(s).",
                resultReferences(metadata, references)
        );
    }

    private String requireModelId() {
        String modelId = properties.getBedrockModelId();
        if (modelId == null || modelId.isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set when Bedrock provider is enabled");
        }
        return modelId.strip();
    }

    private String buildPrompt(
            AnalysisRequestContext context,
            ObjectMetadata metadata,
            List<ReferenceDocument> references
    ) {
        return """
                You are assisting the Terraformers modernization backend.
                Generate a concise Terraform main.tf draft from the stored architecture source reference.

                Constraints:
                - Return Terraform code only.
                - Do not include markdown fences.
                - Do not invent credentials, access keys, or secret values.
                - Use placeholders for account-specific values.
                - Prefer AWS resource patterns supported by the retrieved reference context when relevant.

                Source reference:
                - projectId: %s
                - sourceBucket: %s
                - sourceKey: %s
                - contentType: %s
                - contentLength: %d
                - correlationId: %s

                Retrieved reference context:
                %s
                """.formatted(
                context.projectId(),
                metadata.bucket(),
                metadata.key(),
                metadata.contentType(),
                metadata.contentLength(),
                context.correlationId(),
                formatReferences(references)
        );
    }

    private String formatReferences(List<ReferenceDocument> references) {
        if (references == null || references.isEmpty()) {
            return "- none";
        }

        StringBuilder builder = new StringBuilder();
        for (ReferenceDocument reference : references) {
            builder.append("- id: ").append(reference.id()).append('\n')
                    .append("  title: ").append(reference.title()).append('\n')
                    .append("  score: ").append(reference.score()).append('\n')
                    .append("  content: ").append(truncate(reference.content())).append('\n');
        }
        return builder.toString().stripTrailing();
    }

    private String truncate(String content) {
        if (content == null || content.length() <= MAX_REFERENCE_CONTENT_LENGTH) {
            return content == null ? "" : content;
        }
        return content.substring(0, MAX_REFERENCE_CONTENT_LENGTH) + "...";
    }

    private List<String> resultReferences(ObjectMetadata metadata, List<ReferenceDocument> references) {
        List<String> result = new ArrayList<>();
        result.add("s3://" + metadata.bucket() + "/" + metadata.key());
        if (references != null) {
            references.stream().map(ReferenceDocument::id).forEach(result::add);
        }
        return result;
    }

    private String toAnthropicMessagesRequest(String prompt) {
        try {
            return objectMapper.writeValueAsString(new AnthropicMessagesRequest(
                    ANTHROPIC_VERSION,
                    properties.getBedrockMaxTokens(),
                    List.of(new AnthropicMessage(
                            "user",
                            List.of(new AnthropicContent("text", prompt))
                    ))
            ));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to serialize Bedrock request", exception);
        }
    }

    private String extractText(String responseBody) {
        try {
            JsonNode root = objectMapper.readTree(responseBody);

            JsonNode content = root.path("content");
            if (content.isArray() && !content.isEmpty()) {
                StringBuilder builder = new StringBuilder();
                for (JsonNode item : content) {
                    JsonNode text = item.path("text");
                    if (text.isTextual()) {
                        if (!builder.isEmpty()) {
                            builder.append("\n");
                        }
                        builder.append(text.asText());
                    }
                }
                if (!builder.isEmpty()) {
                    return builder.toString().strip();
                }
            }

            JsonNode outputText = root.path("outputText");
            if (outputText.isTextual()) {
                return outputText.asText().strip();
            }

            JsonNode completion = root.path("completion");
            if (completion.isTextual()) {
                return completion.asText().strip();
            }

            throw new IllegalStateException("Bedrock response did not contain text content");
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to parse Bedrock response", exception);
        }
    }

    private record AnthropicMessagesRequest(
            String anthropic_version,
            int max_tokens,
            List<AnthropicMessage> messages
    ) {
    }

    private record AnthropicMessage(
            String role,
            List<AnthropicContent> content
    ) {
    }

    private record AnthropicContent(
            String type,
            String text
    ) {
    }
}
