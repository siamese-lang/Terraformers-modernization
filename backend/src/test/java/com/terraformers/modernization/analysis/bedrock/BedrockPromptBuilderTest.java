package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectMetadata;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

class BedrockPromptBuilderTest {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final BedrockPromptBuilder builder = new BedrockPromptBuilder(objectMapper);

    @Test
    void buildsClaudeVisionRequestWithoutSecretValues() throws Exception {
        ObjectContent content = new ObjectContent(
                new ObjectMetadata("example-bucket", "uploads/diagram.png", "image/png", 128L, "etag"),
                "fake-image".getBytes(StandardCharsets.UTF_8)
        );

        String request = builder.buildClaudeVisionRequest(content, List.of(
                new ReferenceDocument("ref-1", "VPC pattern", "Use private subnets for database workloads.", 0.9)
        ), 2048);

        JsonNode root = objectMapper.readTree(request);

        assertThat(root.path("anthropic_version").asText()).isEqualTo("bedrock-2023-05-31");
        assertThat(root.path("max_tokens").asInt()).isEqualTo(2048);
        assertThat(request).contains("uploads/diagram.png");
        assertThat(request).contains("VPC pattern");
        assertThat(request).doesNotContain("access_key");
        assertThat(request).doesNotContain("secret_key");
    }

    @Test
    void rejectsUnsupportedContentType() {
        ObjectContent content = new ObjectContent(
                new ObjectMetadata("example-bucket", "uploads/file.txt", "text/plain", 10L, "etag"),
                "not-image".getBytes(StandardCharsets.UTF_8)
        );

        assertThatThrownBy(() -> builder.buildClaudeVisionRequest(content, List.of(), 1024))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("unsupported image content type");
    }
}
