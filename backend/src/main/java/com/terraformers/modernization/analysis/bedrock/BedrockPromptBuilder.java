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

    public static final String RESPONSE_SCHEMA = """
            <analysis_json>
            {
              "summary": "concise architecture summary",
              "components": ["detected service or component names"],
              "relationships": ["directed relationship descriptions"],
              "warnings": ["uncertainty, missing labels, or assumptions"]
            }
            </analysis_json>
            <terraform_hcl>
            complete Terraform HCL containing resource or module blocks
            </terraform_hcl>
            """;

    private final ObjectMapper objectMapper;

    public BedrockPromptBuilder(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String buildClaudeVisionRequest(ObjectContent source, List<ReferenceDocument> references, int maxTokens) {
        String mediaType = requireSupportedImageMediaType(source.metadata().contentType());
        String imageBase64 = Base64.getEncoder().encodeToString(source.bytes());
        String prompt = buildPrompt(source, references == null ? List.of() : references);

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
                Analyze the architecture diagram image and return exactly these two tagged sections, once each:
                %s

                Requirements:
                - Do not include markdown fences or surrounding prose.
                - Do not include `terraformCode` in `analysis_json`.
                - `terraform_hcl` must be raw Terraform HCL, not a JSON string, and must include real `resource` or `module` blocks.
                - Keep Terraform concise and limited to what is needed to describe the analyzed architecture; do not duplicate resources or add verbose comments.
                - Do not include secrets, account IDs, access keys, static credentials, public S3 URLs, or real ARNs.
                - Use placeholders or variables for account-specific values.
                - If the diagram is ambiguous, still include the best-effort components/relationships and put uncertainty in `warnings`.

                Object metadata:
                - contentType: %s
                - contentLength: %s

                Optional reference patterns:
                %s
                """.formatted(
                RESPONSE_SCHEMA.strip(),
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
