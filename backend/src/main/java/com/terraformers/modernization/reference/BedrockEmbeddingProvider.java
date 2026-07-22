package com.terraformers.modernization.reference;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;
import org.springframework.context.annotation.Lazy;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

@Component
public class BedrockEmbeddingProvider implements EmbeddingProvider {

    private final BedrockRuntimeClient client;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;

    public BedrockEmbeddingProvider(@Lazy BedrockRuntimeClient client, ObjectMapper objectMapper, AnalysisRuntimeProperties properties) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    @Override
    public List<Float> embed(String text) {
        requireEmbeddingModelId();
        try {
            String body = objectMapper.writeValueAsString(Map.of("inputText", text));
            InvokeModelResponse response = client.invokeModel(InvokeModelRequest.builder()
                    .modelId(properties.getBedrockEmbeddingModelId())
                    .contentType("application/json")
                    .accept("application/json")
                    .body(SdkBytes.fromUtf8String(body))
                    .build());

            JsonNode embedding = objectMapper.readTree(response.body().asUtf8String()).path("embedding");
            if (!embedding.isArray()) {
                throw new IllegalStateException("Bedrock embedding response does not contain an embedding array");
            }

            List<Float> vector = new ArrayList<>();
            embedding.forEach(value -> vector.add((float) value.asDouble()));
            if (vector.isEmpty()) {
                throw new IllegalStateException("Bedrock embedding response contains an empty embedding array");
            }
            Integer expectedDimension = properties.getExpectedVectorDimension();
            if (expectedDimension != null && vector.size() != expectedDimension) {
                throw new IllegalStateException("Bedrock embedding vector dimension does not match configured expected dimension");
            }
            return vector;
        } catch (Exception exception) {
            throw new IllegalStateException("failed to generate Bedrock embedding", exception);
        }
    }

    private void requireEmbeddingModelId() {
        if (properties.getBedrockEmbeddingModelId() == null || properties.getBedrockEmbeddingModelId().isBlank()) {
            throw new IllegalStateException("terraformers.analysis.bedrock-embedding-model-id must be set when Bedrock embedding is enabled");
        }
    }
}
