package com.terraformers.modernization.analysis;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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

    private final BedrockRuntimeClient bedrockRuntimeClient;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;

    @Autowired
    public BedrockRuntimeAnalysisProvider(ObjectMapper objectMapper, AnalysisRuntimeProperties properties) {
        this(BedrockRuntimeClient.builder().build(), objectMapper, properties);
    }

    BedrockRuntimeAnalysisProvider(
            BedrockRuntimeClient bedrockRuntimeClient,
            ObjectMapper objectMapper,
            AnalysisRuntimeProperties properties
    ) {
        this.bedrockRuntimeClient = bedrockRuntimeClient;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        String modelId = requireModelId();
        String prompt = buildPrompt(context);
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
                "Generated through Bedrock Runtime model " + modelId + " from stored source object metadata.",
                List.of("s3://" + context.sourceBucket() + "/" + context.sourceKey())
        );
    }

    private String requireModelId() {
        String modelId = properties.getBedrockModelId();
        if (modelId == null || modelId.isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set when Bedrock provider is enabled");
        }
        return modelId.strip();
    }

    private String buildPrompt(AnalysisRequestContext context) {
        return """
                You are assisting the Terraformers modernization backend.
                Generate a concise Terraform main.tf draft from the stored architecture source reference.

                Constraints:
                - Return Terraform code only.
                - Do not include markdown fences.
                - Do not invent credentials, access keys, or secret values.
                - Use placeholders for account-specific values.

                Source reference:
                - projectId: %s
                - sourceBucket: %s
                - sourceKey: %s
                - correlationId: %s
                """.formatted(
                context.projectId(),
                context.sourceBucket(),
                context.sourceKey(),
                context.correlationId()
        );
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
