package com.terraformers.modernization.reference;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;

@Component
@Primary
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "opensearch-retriever-enabled", havingValue = "true")
public class OpenSearchReferenceRetriever implements ReferenceRetriever {

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final AnalysisRuntimeProperties properties;

    @Autowired
    public OpenSearchReferenceRetriever(ObjectMapper objectMapper, AnalysisRuntimeProperties properties) {
        this(HttpClient.newHttpClient(), objectMapper, properties);
    }

    OpenSearchReferenceRetriever(
            HttpClient httpClient,
            ObjectMapper objectMapper,
            AnalysisRuntimeProperties properties
    ) {
        this.httpClient = httpClient;
        this.objectMapper = objectMapper;
        this.properties = properties;
    }

    @Override
    public List<ReferenceDocument> retrieve(ReferenceQuery query) {
        String endpoint = requireSetting(properties.getOpensearchEndpoint(), "terraformers.analysis.opensearch-endpoint");
        String indexName = requireSetting(properties.getIndexName(), "terraformers.analysis.index-name");
        String contentField = normalize(properties.getContentFieldName(), "content");
        int limit = resolveLimit(query.limit());

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(endpoint.strip().replaceAll("/+$", "") + "/" + indexName + "/_search"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(buildSearchBody(query, contentField, limit)))
                .build();

        try {
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new IllegalStateException("OpenSearch reference query failed with status " + response.statusCode());
            }
            return parseSearchResults(response.body(), contentField);
        } catch (IOException exception) {
            throw new IllegalStateException("failed to query OpenSearch reference index", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("interrupted while querying OpenSearch reference index", exception);
        }
    }

    private String buildSearchBody(ReferenceQuery query, String contentField, int limit) {
        try {
            String queryText = buildQueryText(query);
            return objectMapper.writeValueAsString(objectMapper.createObjectNode()
                    .put("size", limit)
                    .set("query", objectMapper.createObjectNode()
                            .set("multi_match", objectMapper.createObjectNode()
                                    .put("query", queryText)
                                    .set("fields", objectMapper.createArrayNode()
                                            .add("title^2")
                                            .add(contentField)
                                            .add("service")
                                            .add("tags")))));
        } catch (IOException exception) {
            throw new IllegalStateException("failed to build OpenSearch reference query", exception);
        }
    }

    private String buildQueryText(ReferenceQuery query) {
        List<String> parts = new ArrayList<>();
        addIfPresent(parts, query.projectId());
        addIfPresent(parts, query.contentType());
        addIfPresent(parts, query.sourceKey());
        if (query.detectedServices() != null) {
            query.detectedServices().forEach(service -> addIfPresent(parts, service));
        }
        return parts.isEmpty() ? "terraform architecture reference" : String.join(" ", parts);
    }

    private List<ReferenceDocument> parseSearchResults(String body, String contentField) {
        try {
            JsonNode hits = objectMapper.readTree(body).path("hits").path("hits");
            if (!hits.isArray()) {
                return List.of();
            }

            List<ReferenceDocument> documents = new ArrayList<>();
            for (JsonNode hit : hits) {
                JsonNode source = hit.path("_source");
                documents.add(new ReferenceDocument(
                        readText(hit.path("_id"), source.path("id"), "unknown-reference"),
                        readText(source.path("title"), source.path("name"), "Untitled reference"),
                        readText(source.path(contentField), source.path("content"), ""),
                        hit.path("_score").asDouble(0.0)
                ));
            }
            return documents;
        } catch (IOException exception) {
            throw new IllegalStateException("failed to parse OpenSearch reference results", exception);
        }
    }

    private int resolveLimit(int queryLimit) {
        if (queryLimit > 0) {
            return queryLimit;
        }
        return Math.max(1, properties.getOpensearchTopK());
    }

    private String requireSetting(String value, String propertyName) {
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(propertyName + " must be set when OpenSearch retriever is enabled");
        }
        return value.strip();
    }

    private String normalize(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value.strip();
    }

    private void addIfPresent(List<String> parts, String value) {
        if (value != null && !value.isBlank()) {
            parts.add(value.strip());
        }
    }

    private String readText(JsonNode primary, JsonNode fallback, String defaultValue) {
        if (primary != null && primary.isTextual()) {
            return primary.asText();
        }
        if (fallback != null && fallback.isTextual()) {
            return fallback.asText();
        }
        return defaultValue;
    }
}
