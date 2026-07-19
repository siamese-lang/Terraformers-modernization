package com.terraformers.modernization.analysis.bedrock;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

@Component
public class BedrockResponseParser {

    private static final Pattern ANALYSIS_JSON = Pattern.compile("<analysis_json>(.*?)</analysis_json>", Pattern.DOTALL);
    private static final Pattern TERRAFORM_HCL = Pattern.compile("<terraform_hcl>(.*?)</terraform_hcl>", Pattern.DOTALL);

    private final ObjectMapper objectMapper;

    public BedrockResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public ParsedBedrockAnalysis parse(String responseBody) {
        JsonNode root = parseResponseBody(responseBody);
        String stopReason = root.path("stop_reason").asText(null);
        Integer outputTokens = readOutputTokenCount(root);
        if ("max_tokens".equals(stopReason)) {
            throw new BedrockOutputTruncatedException(stopReason, outputTokens);
        }

        String text = extractResponseText(root);
        String analysisJson = requiredTaggedContent(text, ANALYSIS_JSON, "analysis_json");
        String terraform = requiredTaggedContent(text, TERRAFORM_HCL, "terraform_hcl");
        if (!ANALYSIS_JSON.matcher(TERRAFORM_HCL.matcher(text).replaceAll("")).replaceAll("").isBlank()) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid: unexpected content outside tagged sections");
        }
        try {
            JsonNode structured = objectMapper.readTree(analysisJson);
            String summary = firstText(structured, "summary");
            if (summary.isBlank()) {
                throw new BedrockResponseFormatException("Bedrock analysis_json is missing summary");
            }
            if (structured.has("terraformCode")) {
                throw new BedrockResponseFormatException("Bedrock analysis_json must not contain terraformCode");
            }
            return new ParsedBedrockAnalysis(
                    terraform,
                    summary,
                    textArray(structured, "components"),
                    textArray(structured, "relationships"),
                    textArray(structured, "warnings"),
                    stopReason,
                    outputTokens
            );
        } catch (BedrockResponseFormatException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid", exception);
        }
    }

    public String extractText(String responseBody) {
        return parse(responseBody).terraformCode();
    }

    private JsonNode parseResponseBody(String responseBody) {
        try {
            JsonNode root = objectMapper.readTree(responseBody);
            if (root == null || !root.isObject()) {
                throw new BedrockResponseFormatException("Bedrock response format is invalid");
            }
            return root;
        } catch (Exception exception) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid", exception);
        }
    }

    private Integer readOutputTokenCount(JsonNode root) {
        JsonNode outputTokens = root.path("usage").path("output_tokens");
        if (outputTokens.canConvertToInt()) {
            return outputTokens.asInt();
        }
        return null;
    }

    private String extractResponseText(JsonNode root) {
        try {
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
            throw new BedrockResponseFormatException("Bedrock response format is invalid", exception);
        }
    }

    private String requiredTaggedContent(String text, Pattern pattern, String tagName) {
        Matcher matcher = pattern.matcher(text);
        if (!matcher.find()) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid: must contain exactly one " + tagName + " section");
        }
        String content = matcher.group(1).strip();
        if (matcher.find()) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid: must contain exactly one " + tagName + " section");
        }
        if (content.isBlank()) {
            throw new BedrockResponseFormatException("Bedrock response format is invalid: " + tagName + " section is empty");
        }
        return content;
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

}
