package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

class BedrockResponseParserTest {

    private final BedrockResponseParser parser = new BedrockResponseParser(new ObjectMapper());

    @Test
    void parsesStructuredAnalysisSchemaFromClaudeResponse() {
        String response = """
                {
                  "content": [
                    {"type": "text", "text": "{\"summary\":\"VPC with public web tier\",\"components\":[\"VPC\",\"ALB\"],\"relationships\":[\"ALB routes to web tier\"],\"warnings\":[\"CIDRs are inferred\"],\"terraformCode\":\"resource \\\"aws_vpc\\\" \\\"main\\\" { cidr_block = \\\"10.0.0.0/16\\\" }\"}"}
                  ]
                }
                """;

        ParsedBedrockAnalysis parsed = parser.parse(response);

        assertThat(parsed.summary()).isEqualTo("VPC with public web tier");
        assertThat(parsed.components()).containsExactly("VPC", "ALB");
        assertThat(parsed.relationships()).containsExactly("ALB routes to web tier");
        assertThat(parsed.warnings()).containsExactly("CIDRs are inferred");
        assertThat(parsed.terraformCode()).contains("resource \"aws_vpc\"");
    }

    @Test
    void rejectsUnstructuredTerraformText() {
        String response = """
                {"content":[{"type":"text","text":"resource \\\"aws_s3_bucket\\\" \\\"example\\\" {}"}]}
                """;

        assertThatThrownBy(() -> parser.parse(response))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("structured analysis schema");
    }
}
