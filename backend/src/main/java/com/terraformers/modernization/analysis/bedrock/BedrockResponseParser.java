package com.terraformers.modernization.analysis.bedrock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class BedrockResponseParser {

    private final ObjectMapper objectMapper;

    public BedrockResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public ParsedBedrockAnalysis parse(String responseBody) {
        String text = extractResponseText(responseBody);
        try {
            JsonNode structured = objectMapper.readTree(stripMarkdownFence(text));
            String terraform = firstText(structured, "terraformCode");
            String summary = firstText(structured, "summary");
            if (terraform.isBlank()) {
                throw new IllegalStateException("Bedrock structured response is missing terraformCode");
            }
            if (summary.isBlank()) {
                throw new IllegalStateException("Bedrock structured response is missing summary");
            }
            return new ParsedBedrockAnalysis(
                    stripMarkdownFence(terraform),
                    summary,
                    textArray(structured, "components"),
                    textArray(structured, "relationships"),
                    textArray(structured, "warnings")
            );
        } catch (Exception exception) {
            throw new IllegalStateException("Bedrock response must be JSON matching the structured analysis schema", exception);
        }
    }

    public String extractText(String responseBody) {
        return parse(responseBody).terraformCode();
    }

    private String extractResponseText(String responseBody) {
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
            return text;
        } catch (Exception exception) {
            throw new IllegalStateException("failed to parse Bedrock response", exception);
        }
    }

    private String firstText(JsonNode node, String... names) {
        for (String name : names) {
            JsonNode value = node.path(name);
            if (value.isTextual() && !value.asText().isBlank()) return value.asText().strip();
        }
        return "";
    }

    private List<String> textArray(JsonNode node, String... names) {
        for (String name : names) {
            JsonNode value = node.path(name);
            if (value.isArray()) {
                List<String> result = new ArrayList<>();
                value.forEach(item -> { if (item.isTextual() && !item.asText().isBlank()) result.add(item.asText().strip()); else if (item.isObject()) result.add(item.toString()); });
                return result;
            }
        }
        return List.of();
    }

    private String stripMarkdownFence(String text) {
        String stripped = text == null ? "" : text.strip();
        if (!stripped.startsWith("```")) {
            return stripped;
        }
        String withoutOpening = stripped.replaceFirst("^```[a-zA-Z0-9_-]*\\s*", "");
        return withoutOpening.replaceFirst("\\s*```$", "").strip();
    }
}
