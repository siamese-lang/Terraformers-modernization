package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

class BedrockResponseParserTest {

    private final BedrockResponseParser parser = new BedrockResponseParser(new ObjectMapper());

    @Test
    void extractsPlainTextFromClaudeResponse() {
        String response = """
                {
                  "content": [
                    {"type": "text", "text": "provider \\\"aws\\\" {\\n  region = var.aws_region\\n}"}
                  ]
                }
                """;

        String parsed = parser.extractText(response);

        assertThat(parsed).contains("provider \"aws\"");
        assertThat(parsed).doesNotContain("```");
    }

    @Test
    void stripsMarkdownFenceWhenModelReturnsCodeBlock() {
        String response = """
                {
                  "content": [
                    {"type": "text", "text": "```hcl\\nprovider \\\"aws\\\" {}\\n```"}
                  ]
                }
                """;

        String parsed = parser.extractText(response);

        assertThat(parsed).isEqualTo("provider \"aws\" {}");
    }
}
