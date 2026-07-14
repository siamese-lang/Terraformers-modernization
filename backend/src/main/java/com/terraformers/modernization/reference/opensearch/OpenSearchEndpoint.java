package com.terraformers.modernization.reference.opensearch;

import java.net.URI;

public final class OpenSearchEndpoint {

    private OpenSearchEndpoint() {
    }

    public static URI searchUri(String endpoint, String indexName) {
        if (endpoint == null || endpoint.isBlank()) {
            throw new IllegalArgumentException("OpenSearch endpoint must be set");
        }
        if (indexName == null || indexName.isBlank()) {
            throw new IllegalArgumentException("OpenSearch index name must be set");
        }

        String normalized = endpoint.strip();
        if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
            normalized = "https://" + normalized;
        }
        if (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return URI.create(normalized + "/" + indexName + "/_search");
    }
}
