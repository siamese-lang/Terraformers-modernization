package com.terraformers.modernization.reference.opensearch;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class OpenSearchResponseParser {

    private final ObjectMapper objectMapper;

    public OpenSearchResponseParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public List<ReferenceDocument> parse(String responseBody, String contentFieldName) {
        try {
            JsonNode hits = objectMapper.readTree(responseBody).path("hits").path("hits");
            if (!hits.isArray()) {
                return List.of();
            }

            List<ReferenceDocument> documents = new ArrayList<>();
            for (JsonNode hit : hits) {
                JsonNode source = hit.path("_source");
                String id = textOrFallback(source.path("id"), hit.path("_id").asText("unknown-reference"));
                String title = textOrFallback(source.path("title"), id);
                String content = source.path(contentFieldName).asText("");
                double score = hit.path("_score").asDouble(0.0);
                documents.add(new ReferenceDocument(id, title, content, score));
            }
            return documents;
        } catch (Exception exception) {
            throw new IllegalStateException("failed to parse OpenSearch response", exception);
        }
    }

    private String textOrFallback(JsonNode node, String fallback) {
        if (node == null || node.isMissingNode() || node.asText().isBlank()) {
            return fallback;
        }
        return node.asText();
    }
}
