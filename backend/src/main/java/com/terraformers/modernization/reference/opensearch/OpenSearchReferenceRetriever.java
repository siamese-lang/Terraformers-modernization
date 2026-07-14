package com.terraformers.modernization.reference.opensearch;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.EmbeddingProvider;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import com.terraformers.modernization.reference.ReferenceRetriever;
import java.net.URI;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "opensearch-retriever-enabled", havingValue = "true")
public class OpenSearchReferenceRetriever implements ReferenceRetriever {

    private final EmbeddingProvider embeddingProvider;
    private final OpenSearchKnnQueryBuilder queryBuilder;
    private final OpenSearchResponseParser responseParser;
    private final SignedOpenSearchHttpClient httpClient;
    private final AnalysisRuntimeProperties properties;

    public OpenSearchReferenceRetriever(
            EmbeddingProvider embeddingProvider,
            OpenSearchKnnQueryBuilder queryBuilder,
            OpenSearchResponseParser responseParser,
            SignedOpenSearchHttpClient httpClient,
            AnalysisRuntimeProperties properties
    ) {
        this.embeddingProvider = embeddingProvider;
        this.queryBuilder = queryBuilder;
        this.responseParser = responseParser;
        this.httpClient = httpClient;
        this.properties = properties;
    }

    @Override
    public List<ReferenceDocument> retrieve(ReferenceQuery query) {
        requireRuntimeConfig();

        String embeddingText = toEmbeddingText(query);
        List<Float> vector = embeddingProvider.embed(embeddingText);
        int topK = properties.getOpensearchTopK() > 0 ? properties.getOpensearchTopK() : query.limit();
        String body = queryBuilder.build(
                properties.getVectorFieldName(),
                properties.getContentFieldName(),
                vector,
                topK
        );
        URI uri = OpenSearchEndpoint.searchUri(properties.getOpensearchEndpoint(), properties.getIndexName());
        String response = httpClient.post(uri, body, properties.getOpensearchServiceName());
        return responseParser.parse(response, properties.getContentFieldName());
    }

    private String toEmbeddingText(ReferenceQuery query) {
        String services = query.detectedServices() == null || query.detectedServices().isEmpty()
                ? "unknown-services"
                : query.detectedServices().stream().collect(Collectors.joining(", "));
        return "projectId=%s source=s3://%s/%s contentType=%s services=%s".formatted(
                query.projectId(),
                query.sourceBucket(),
                query.sourceKey(),
                query.contentType(),
                services
        );
    }

    private void requireRuntimeConfig() {
        if (isBlank(properties.getOpensearchEndpoint())) {
            throw new IllegalStateException("terraformers.analysis.opensearch-endpoint must be set when OpenSearch retriever is enabled");
        }
        if (isBlank(properties.getIndexName())) {
            throw new IllegalStateException("terraformers.analysis.index-name must be set when OpenSearch retriever is enabled");
        }
        if (isBlank(properties.getVectorFieldName())) {
            throw new IllegalStateException("terraformers.analysis.vector-field-name must be set when OpenSearch retriever is enabled");
        }
        if (isBlank(properties.getContentFieldName())) {
            throw new IllegalStateException("terraformers.analysis.content-field-name must be set when OpenSearch retriever is enabled");
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
