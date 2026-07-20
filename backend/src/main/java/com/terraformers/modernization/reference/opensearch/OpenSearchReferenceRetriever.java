package com.terraformers.modernization.reference.opensearch;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.EmbeddingProvider;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import java.net.URI;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
public class OpenSearchReferenceRetriever {

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

    public List<ReferenceDocument> retrieve(ReferenceQuery query) {
        requireRuntimeConfig();

        List<Float> vector = embeddingProvider.embed(query.text());
        int topK = properties.getOpensearchTopK();
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
        if (isBlank(properties.getBedrockEmbeddingModelId())) {
            throw new IllegalStateException("terraformers.analysis.bedrock-embedding-model-id must be set for active retrieval");
        }
        if (isBlank(properties.getOpensearchServiceName())) {
            throw new IllegalStateException("terraformers.analysis.opensearch-service-name must be set for active retrieval");
        }
        if (properties.getOpensearchTopK() <= 0) {
            throw new IllegalStateException("terraformers.analysis.opensearch-top-k must be positive for active retrieval");
        }
        if (properties.getExpectedVectorDimension() != null && properties.getExpectedVectorDimension() <= 0) {
            throw new IllegalStateException("terraformers.analysis.expected-vector-dimension must be positive when set");
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
