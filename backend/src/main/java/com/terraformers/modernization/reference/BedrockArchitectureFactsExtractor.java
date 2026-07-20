package com.terraformers.modernization.reference;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.storage.ObjectContent;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;

/** Bounded vision stage used only to derive retrieval facts, never Terraform. */
@Component
public class BedrockArchitectureFactsExtractor {
    private final BedrockRuntimeClient client;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;

    public BedrockArchitectureFactsExtractor(@Lazy BedrockRuntimeClient client, ObjectMapper objectMapper,
                                             AnalysisRuntimeProperties properties) {
        this.client = client;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    public ArchitectureRetrievalFacts extract(ObjectContent source) {
        try {
            String mediaType = source.metadata().contentType();
            String request = objectMapper.writeValueAsString(Map.of(
                    "anthropic_version", "bedrock-2023-05-31", "max_tokens", 300, "temperature", 0,
                    "messages", List.of(Map.of("role", "user", "content", List.of(
                            Map.of("type", "image", "source", Map.of("type", "base64", "media_type", mediaType,
                                    "data", Base64.getEncoder().encodeToString(source.bytes()))),
                            Map.of("type", "text", "text", "Return JSON only: {summary,components,relationships,resourceTypes}. Describe architecture facts only; never generate Terraform."))))));
            String response = client.invokeModel(InvokeModelRequest.builder().modelId(requireModelId())
                    .contentType("application/json").accept("application/json").body(SdkBytes.fromUtf8String(request)).build())
                    .body().asUtf8String();
            JsonNode root = objectMapper.readTree(response);
            JsonNode content = root.path("content");
            if (!content.isArray()) throw new IllegalStateException("Bedrock facts response has no content array");
            JsonNode textBlock = null;
            for (JsonNode block : content) {
                if ("text".equals(block.path("type").asText()) && block.path("text").isTextual()) { textBlock = block; break; }
            }
            if (textBlock == null) throw new IllegalStateException("Bedrock facts response has no text block");
            String text = normalizeFactsJson(textBlock.path("text").asText());
            JsonNode facts = objectMapper.readTree(text);
            if (!facts.isObject()) throw new IllegalStateException("Bedrock facts response is not a JSON object");
            if (!facts.path("summary").isMissingNode() && !facts.path("summary").isTextual()) throw new IllegalStateException("Bedrock facts summary must be text");
            ArchitectureRetrievalFacts result = new ArchitectureRetrievalFacts(facts.path("summary").asText(""), strings(facts.path("components")),
                    strings(facts.path("relationships")), strings(facts.path("resourceTypes")));
            if (result.isEmpty()) throw new IllegalStateException("Bedrock facts response is empty");
            return result;
        } catch (Exception exception) {
            throw new IllegalStateException("failed to extract architecture retrieval facts", exception);
        }
    }

    private String normalizeFactsJson(String responseText) {
        String normalized = responseText.strip();
        if (!normalized.startsWith("```")) return normalized;

        int contentStart = normalized.indexOf('\n');
        int contentEnd = normalized.lastIndexOf("```");
        if (contentStart < 0 || contentEnd <= contentStart) {
            throw new IllegalStateException("Bedrock facts response has an invalid JSON code fence");
        }
        return normalized.substring(contentStart + 1, contentEnd).strip();
    }

    private String requireModelId() {
        String id = properties.getBedrockModelId();
        if (id == null || id.isBlank()) throw new IllegalStateException("terraformers.analysis.bedrock-model-id must be set for retrieval facts");
        return id.strip();
    }

    private List<String> strings(JsonNode node) {
        if (node.isMissingNode()) return List.of();
        if (!node.isArray()) throw new IllegalStateException("Bedrock facts collection must be an array");
        java.util.ArrayList<String> values = new java.util.ArrayList<>();
        node.forEach(value -> {
            if (!value.isTextual()) throw new IllegalStateException("Bedrock facts collection elements must be text");
            values.add(value.asText());
        });
        return values;
    }
}
