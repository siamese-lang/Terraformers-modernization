package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class BedrockResponseParserTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final BedrockResponseParser parser = new BedrockResponseParser(objectMapper);

    @Test
    void parsesTaggedAnalysisJsonAndRawTerraformHcl() throws Exception {
        ParsedBedrockAnalysis parsed = parser.parse(claudeResponse("""
                <analysis_json>
                {"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"VPC with public web tier","components":["VPC","ALB"],"relationships":["ALB routes to web tier"],"warnings":["CIDRs are inferred"]}
                </analysis_json>
                <terraform_hcl>
                resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }
                </terraform_hcl>
                """));

        assertThat(parsed.summary()).isEqualTo("VPC with public web tier");
        assertThat(parsed.components()).containsExactly("VPC", "ALB");
        assertThat(parsed.relationships()).containsExactly("ALB routes to web tier");
        assertThat(parsed.warnings()).containsExactly("CIDRs are inferred");
        assertThat(parsed.terraformCode()).contains("resource \"aws_vpc\"");
        assertThat(parsed.stopReason()).isNull();
        assertThat(parsed.outputTokens()).isNull();
    }

    @Test
    void parsesResponseWhenAnalysisJsonAndTerraformHclEachAppearExactlyOnce() throws Exception {
        ParsedBedrockAnalysis parsed = parser.parse(claudeResponse("""
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"S3 bucket","components":[],"relationships":[],"warnings":[]}</analysis_json>
                <terraform_hcl>resource "aws_s3_bucket" "main" {}</terraform_hcl>
                """));

        assertThat(parsed.summary()).isEqualTo("S3 bucket");
        assertThat(parsed.terraformCode()).isEqualTo("resource \"aws_s3_bucket\" \"main\" {}");
    }

    @Test
    void rejectsMissingRequiredTag() throws Exception {
        assertFormatFailure("<analysis_json>{\"summary\":\"S3\"}</analysis_json>");
    }

    @Test
    void rejectsDuplicateRequiredTag() throws Exception {
        assertFormatFailure("""
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"S3"}</analysis_json>
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"duplicate"}</analysis_json>
                <terraform_hcl>resource "aws_s3_bucket" "main" {}</terraform_hcl>
                """);
    }

    @Test
    void rejectsEmptyRequiredTag() throws Exception {
        assertFormatFailure("<analysis_json>   </analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
    }

    @Test
    void doesNotThrowIllegalStateExceptionForValidTaggedResponse() throws Exception {
        assertThatCode(() -> parser.parse(claudeResponse("""
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"S3","components":[],"relationships":[],"warnings":[]}</analysis_json>
                <terraform_hcl>resource "aws_s3_bucket" "main" {}</terraform_hcl>
                """)))
                .doesNotThrowAnyException();
    }

    @Test
    void preservesQuotesNewlinesAndInterpolationInRawHcl() throws Exception {
        ParsedBedrockAnalysis parsed = parser.parse(claudeResponse("""
                <analysis_json>{"inputType":"ARCHITECTURE_DIAGRAM","classificationConfidence":0.95,"classificationReason":"Components have relationships.","summary":"S3 bucket","components":[],"relationships":[],"warnings":[]}</analysis_json>
                <terraform_hcl>
                resource "aws_s3_bucket" "logs" {
                  bucket = "${var.name}-logs"
                }
                </terraform_hcl>
                """));

        assertThat(parsed.terraformCode()).isEqualTo("""
                resource "aws_s3_bucket" "logs" {
                  bucket = "${var.name}-logs"
                }""");
    }

    @Test
    void rejectsMaxTokensStopReasonAsTruncatedOutput() throws Exception {
        String response = claudeResponse("partial", Map.of("stop_reason", "max_tokens", "usage", Map.of("output_tokens", 2048)));

        assertThatThrownBy(() -> parser.parse(response))
                .isInstanceOfSatisfying(BedrockOutputTruncatedException.class, exception -> {
                    assertThat(exception.getStopReason()).isEqualTo("max_tokens");
                    assertThat(exception.getOutputTokens()).isEqualTo(2048);
                });
    }

    @Test
    void preservesNormalStopReasonAndOutputTokens() throws Exception {
        ParsedBedrockAnalysis parsed = parser.parse(claudeResponse(
                "<analysis_json>{\"inputType\":\"ARCHITECTURE_DIAGRAM\",\"classificationConfidence\":0.95,\"classificationReason\":\"Components have relationships.\",\"summary\":\"S3\",\"components\":[],\"relationships\":[],\"warnings\":[]}</analysis_json>"
                        + "<terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>",
                Map.of("stop_reason", "end_turn", "usage", Map.of("output_tokens", 321))));

        assertThat(parsed.stopReason()).isEqualTo("end_turn");
        assertThat(parsed.outputTokens()).isEqualTo(321);
    }

    @Test
    void rejectsInvalidAnalysisJson() throws Exception {
        assertFormatFailure("<analysis_json>{invalid}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
    }

    @Test
    void rejectsNonArchitectureAndAmbiguousInputsWithoutReturningTerraform() throws Exception {
        for (String inputType : List.of("NON_ARCHITECTURE_IMAGE", "AMBIGUOUS")) {
            assertThatThrownBy(() -> parser.parse(claudeResponse("""
                    <analysis_json>{"inputType":"%s","classificationConfidence":0.5,"classificationReason":"The system structure is not identifiable.","summary":"","components":[],"relationships":[],"warnings":[]}</analysis_json>
                    <terraform_hcl>resource "aws_s3_bucket" "must_not_be_used" {}</terraform_hcl>
                    """.formatted(inputType))))
                    .isInstanceOf(ArchitectureInputRejectedException.class);
        }
    }

    @Test
    void rejectsMissingOrInvalidClassificationMetadata() throws Exception {
        assertFormatFailure("<analysis_json>{\"summary\":\"S3\"}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
        assertFormatFailure("<analysis_json>{\"inputType\":\"UNKNOWN\",\"classificationConfidence\":0.5,\"classificationReason\":\"reason\",\"summary\":\"S3\"}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
        assertFormatFailure("<analysis_json>{\"inputType\":\"ARCHITECTURE_DIAGRAM\",\"classificationConfidence\":1.1,\"classificationReason\":\"reason\",\"summary\":\"S3\"}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
        assertFormatFailure("<analysis_json>{\"inputType\":\"ARCHITECTURE_DIAGRAM\",\"classificationConfidence\":0.5,\"classificationReason\":\" \",\"summary\":\"S3\"}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
    }

    @Test
    void rejectsMissingClosingTag() throws Exception {
        assertFormatFailure("<analysis_json>{\"summary\":\"S3\"}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}");
    }

    @Test
    void rejectsMissingSummary() throws Exception {
        assertFormatFailure("<analysis_json>{\"components\":[]}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
    }

    @Test
    void rejectsMissingOrBlankTerraformHcl() throws Exception {
        assertFormatFailure("<analysis_json>{\"summary\":\"S3\"}</analysis_json>");
        assertFormatFailure("<analysis_json>{\"summary\":\"S3\"}</analysis_json><terraform_hcl>   </terraform_hcl>");
    }

    @Test
    void rejectsUnstructuredTerraformText() throws Exception {
        assertFormatFailure("resource \"aws_s3_bucket\" \"example\" {}");
    }

    private void assertFormatFailure(String text) throws Exception {
        assertThatThrownBy(() -> parser.parse(claudeResponse(text)))
                .isInstanceOf(BedrockResponseFormatException.class)
                .hasMessageContaining("format");
    }

    private String claudeResponse(String text) throws Exception {
        return claudeResponse(text, Map.of());
    }

    private String claudeResponse(String text, Map<String, Object> metadata) throws Exception {
        Map<String, Object> response = new java.util.HashMap<>(metadata);
        response.put("content", List.of(Map.of("type", "text", "text", text)));
        return objectMapper.writeValueAsString(response);
    }
}
