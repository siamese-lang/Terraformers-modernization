package com.terraformers.modernization.analysis.bedrock;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.storage.ObjectContent;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

@Component
public class BedrockPromptBuilder {

    private final ObjectMapper objectMapper;

    public BedrockPromptBuilder(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String buildClaudeVisionRequest(ObjectContent source, List<ReferenceDocument> references, int maxTokens) {
        String mediaType = requireSupportedImageMediaType(source.metadata().contentType());
        String imageBase64 = Base64.getEncoder().encodeToString(source.bytes());
        String prompt = buildPrompt(source, references);

        Map<String, Object> body = Map.of(
                "anthropic_version", "bedrock-2023-05-31",
                "max_tokens", maxTokens,
                "temperature", 0.2,
                "messages", List.of(Map.of(
                        "role", "user",
                        "content", List.of(
                                Map.of(
                                        "type", "image",
                                        "source", Map.of(
                                                "type", "base64",
                                                "media_type", mediaType,
                                                "data", imageBase64
                                        )
                                ),
                                Map.of(
                                        "type", "text",
                                        "text", prompt
                                )
                        )
                ))
        );

        try {
            return objectMapper.writeValueAsString(body);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("failed to build Bedrock request body", exception);
        }
    }

    private String buildPrompt(ObjectContent source, List<ReferenceDocument> references) {
        String referenceText = references.stream()
                .map(reference -> "- " + reference.title() + ": " + reference.content())
                .collect(Collectors.joining("\n"));

        return """
                You are analyzing an AWS architecture diagram for the Terraformers modernization backend.

                Task:
                1. Decide whether the image is an AWS architecture diagram.
                2. Identify the AWS services and relationships visible in the image.
                3. Generate a Terraform draft in HCL for review, not direct production apply.

                Object metadata:
                - bucket: %s
                - key: %s
                - contentType: %s
                - contentLength: %s

                Reference patterns:
                %s

                Output format:
                - Return only Terraform HCL.
                - Do not include markdown fences.
                - Do not include secrets, account IDs, access keys, or real ARNs.
                - Use placeholders for account-specific values.
                """.formatted(
                source.metadata().bucket(),
                source.metadata().key(),
                source.metadata().contentType(),
                source.metadata().contentLength(),
                referenceText.isBlank() ? "- none" : referenceText
        );
    }

    private String requireSupportedImageMediaType(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            throw new IllegalArgumentException("source object content type is required for Bedrock vision request");
        }

        String normalized = contentType.toLowerCase();
        if (normalized.equals("image/png")
                || normalized.equals("image/jpeg")
                || normalized.equals("image/webp")
                || normalized.equals("image/gif")) {
            return normalized;
        }

        throw new IllegalArgumentException("unsupported image content type for Bedrock vision request: " + contentType);
    }
}
