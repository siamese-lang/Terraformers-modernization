package com.terraformers.modernization.analysis.bedrock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;

@Component
public class BedrockResponseParser {

    private final ObjectMapper objectMapper;

    public BedrockResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public String extractText(String responseBody) {
        try {
            JsonNode root = objectMapper.readTree(responseBody);
            JsonNode content = root.path("content");
            if (!content.isArray()) {
                throw new IllegalStateException("Bedrock response does not contain content array");
            }

            StringBuilder builder = new StringBuilder();
            for (JsonNode item : content) {
                if ("text".equals(item.path("type").asText())) {
                    builder.append(item.path("text").asText());
                }
            }

            String text = builder.toString().strip();
            if (text.isBlank()) {
                throw new IllegalStateException("Bedrock response text is empty");
            }

            return stripMarkdownFence(text);
        } catch (Exception exception) {
            throw new IllegalStateException("failed to parse Bedrock response", exception);
        }
    }

    private String stripMarkdownFence(String text) {
        String stripped = text.strip();
        if (!stripped.startsWith("```")) {
            return stripped;
        }

        String withoutOpening = stripped.replaceFirst("^```[a-zA-Z0-9_-]*\\s*", "");
        return withoutOpening.replaceFirst("\\s*```$", "").strip();
    }
}
