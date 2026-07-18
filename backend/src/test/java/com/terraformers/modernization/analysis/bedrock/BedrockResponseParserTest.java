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
    void parsesStructuredAnalysisSchemaFromClaudeResponse() throws Exception {
        String response = claudeResponse(Map.of(
                "summary", "VPC with public web tier",
                "components", List.of("VPC", "ALB"),
                "relationships", List.of("ALB routes to web tier"),
                "warnings", List.of("CIDRs are inferred"),
                "terraformCode", "resource \"aws_vpc\" \"main\" { cidr_block = \"10.0.0.0/16\" }"
        ));

        ParsedBedrockAnalysis parsed = parser.parse(response);

        assertThat(parsed.summary()).isEqualTo("VPC with public web tier");
        assertThat(parsed.components()).containsExactly("VPC", "ALB");
        assertThat(parsed.relationships()).containsExactly("ALB routes to web tier");
        assertThat(parsed.warnings()).containsExactly("CIDRs are inferred");
        assertThat(parsed.terraformCode()).contains("resource \"aws_vpc\"");
    }

    @Test
    void rejectsUnstructuredTerraformText() throws Exception {
        String response = objectMapper.writeValueAsString(Map.of(
                "content", List.of(Map.of(
                        "type", "text",
                        "text", "resource \"aws_s3_bucket\" \"example\" {}"
                ))
        ));

        assertThatThrownBy(() -> parser.parse(response))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("structured analysis schema");
    }

    @Test
    void rejectsMissingSummary() throws Exception {
        String response = claudeResponse(Map.of(
                "components", List.of("S3"),
                "relationships", List.of(),
                "warnings", List.of(),
                "terraformCode", "resource \"aws_s3_bucket\" \"main\" {}"
        ));

        assertThatThrownBy(() -> parser.parse(response))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("structured analysis schema");
    }

    private String claudeResponse(Map<String, Object> structured) throws Exception {
        return objectMapper.writeValueAsString(Map.of(
                "content", List.of(Map.of(
                        "type", "text",
                        "text", objectMapper.writeValueAsString(structured)
                ))
        ));
    }
}
