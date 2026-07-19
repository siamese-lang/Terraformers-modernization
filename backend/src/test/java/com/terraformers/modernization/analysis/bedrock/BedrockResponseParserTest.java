package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
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
                {"summary":"VPC with public web tier","components":["VPC","ALB"],"relationships":["ALB routes to web tier"],"warnings":["CIDRs are inferred"]}
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
    }

    @Test
    void preservesQuotesNewlinesAndInterpolationInRawHcl() throws Exception {
        ParsedBedrockAnalysis parsed = parser.parse(claudeResponse("""
                <analysis_json>{"summary":"S3 bucket","components":[],"relationships":[],"warnings":[]}</analysis_json>
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

        assertThatThrownBy(() -> parser.parse(response)).isInstanceOf(BedrockOutputTruncatedException.class);
    }

    @Test
    void rejectsInvalidAnalysisJson() throws Exception {
        assertFormatFailure("<analysis_json>{invalid}</analysis_json><terraform_hcl>resource \"aws_s3_bucket\" \"main\" {}</terraform_hcl>");
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
