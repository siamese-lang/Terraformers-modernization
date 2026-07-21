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
              "inputType": "ARCHITECTURE_DIAGRAM",
              "classificationConfidence": 0.0,
              "classificationReason": "one short sentence explaining the classification",
              "summary": "concise architecture summary",
              "components": ["detected service or component names"],
              "relationships": ["directed relationship descriptions"],
              "warnings": ["uncertainty, missing labels, or assumptions"]
            }
            </analysis_json>
            <terraform_hcl>
            resource "example" "architecture" {}
            </terraform_hcl>
            """;

    private final ObjectMapper objectMapper;

    public BedrockPromptBuilder(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String buildClaudeVisionRequest(ObjectContent source, List<ReferenceDocument> references, int maxTokens) {
        return buildClaudeVisionRequest(source, references, maxTokens, BedrockPromptMode.STANDARD);
    }

    public String buildClaudeVisionRequest(
            ObjectContent source,
            List<ReferenceDocument> references,
            int maxTokens,
            BedrockPromptMode promptMode
    ) {
        String mediaType = requireSupportedImageMediaType(source.metadata().contentType());
        String imageBase64 = Base64.getEncoder().encodeToString(source.bytes());
        String prompt = buildPrompt(source, references == null ? List.of() : references, promptMode);

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

    private String buildPrompt(ObjectContent source, List<ReferenceDocument> references, BedrockPromptMode promptMode) {
        String referenceText = references.stream()
                .map(this::formatReference)
                .collect(Collectors.joining("\n"));

        return """
                Analyze the image and return exactly these two tagged sections, once each:
                %s

                Requirements:
                - Do not include markdown fences or surrounding prose.
                - Do not include `terraformCode` in `analysis_json`.
                - `inputType` must be exactly one of `ARCHITECTURE_DIAGRAM`, `NON_ARCHITECTURE_IMAGE`, or `AMBIGUOUS`.
                - First classify `inputType`. ARCHITECTURE_DIAGRAM requires deployable system components and at least one identifiable connection, flow, dependency, containment, network boundary, or tier relationship that explains a system, deployment, network, service integration, or data flow.
                - Accept cloud, on-premises, WEB/WAS/DB, Kubernetes, API/message-flow, hand-drawn, and ordinary boxes-and-arrows architecture diagrams. Do not accept an image solely because it contains AWS or cloud icons.
                - Classify photos, logos, isolated icons, memes, posters, banners, application or console UI screenshots, documents, tables, receipts, unrelated charts, and unconnected cloud-icon collections as NON_ARCHITECTURE_IMAGE. Use AMBIGUOUS when system meaning or relationships cannot be determined, labels are insufficient, or the diagram is cropped.
                - For NON_ARCHITECTURE_IMAGE or AMBIGUOUS, return empty summary/components/relationships/warnings and leave the contents between `<terraform_hcl>` and `</terraform_hcl>` completely empty; do not infer resources, produce examples, recommendations, templates, or any Terraform.
                - Only for ARCHITECTURE_DIAGRAM, `terraform_hcl` must be raw Terraform HCL, not a JSON string, and must include real `resource` or `module` blocks.
                - Keep Terraform concise and limited to what is needed to describe the analyzed architecture; do not duplicate resources or add verbose comments.
                - Do not include secrets, account IDs, access keys, static credentials, public S3 URLs, or real ARNs.
                - Use placeholders or variables for account-specific values.
                - Treat `PROJECT_DECISION` references as mandatory project constraints when they apply.
                - Use `PROVIDER_SCHEMA` references to determine valid arguments and nested blocks for AWS Provider 5.100.0.
                - Provider examples demonstrate syntax only. Do not copy settings marked by `riskTags` without adapting them to the project constraints.

                %s

                Object metadata:
                - contentType: %s
                - contentLength: %s

                Optional reference patterns:
                %s
                """.formatted(
                RESPONSE_SCHEMA.strip(),
                modeInstructions(promptMode),
                source.metadata().contentType(),
                source.metadata().contentLength(),
                referenceText.isBlank() ? "- none" : referenceText
        );
    }

    private String formatReference(ReferenceDocument reference) {
        String authority = reference.authority() == null || reference.authority().isBlank()
                ? "REFERENCE"
                : reference.authority();
        String source = reference.sourcePath() == null || reference.sourcePath().isBlank()
                ? reference.id()
                : reference.sourcePath();
        String risks = reference.riskTags().isEmpty() ? "none" : String.join(",", reference.riskTags());
        return "- authority=%s; type=%s; source=%s; riskTags=%s; title=%s:\n%s".formatted(
                authority,
                reference.documentType() == null ? "" : reference.documentType(),
                source,
                risks,
                reference.title(),
                reference.content()
        );
    }

    private String modeInstructions(BedrockPromptMode promptMode) {
        if (promptMode == BedrockPromptMode.COMPACT) {
            return """
                    Compact-output requirements (prioritize fitting within the output limit):
                    - Keep summary to one short paragraph; include only core components, communication/dependency relationships, and material uncertainties.
                    - Do not repeat equivalent facts or put object descriptions or lengthy rationale in arrays.
                    - Generate only the core Terraform draft that represents the analyzed architecture.
                    - Use count, for_each, or other concise expressions for repeated resource types; never copy repeated resource blocks.
                    - Exclude provider blocks, lengthy comments, README-style explanations, example commands, unnecessary outputs, data sources, and detailed operational options.
                    - Do not invent resources absent from the image. This is a Terraform draft, not a complete production deployment.
                    """;
        }
        return """
                Standard-output requirements:
                - Keep the analysis and Terraform draft concise; do not repeat equivalent details.
                """;
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
