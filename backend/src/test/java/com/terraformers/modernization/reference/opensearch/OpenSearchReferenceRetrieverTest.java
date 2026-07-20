package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.EmbeddingProvider;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import java.net.URI;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

class OpenSearchReferenceRetrieverTest {
    @Test
    void runsEmbeddingKnnSignedSearchAndResponseParsingInOrder() {
        EmbeddingProvider embedding = mock(EmbeddingProvider.class);
        OpenSearchKnnQueryBuilder queryBuilder = mock(OpenSearchKnnQueryBuilder.class);
        OpenSearchResponseParser parser = mock(OpenSearchResponseParser.class);
        SignedOpenSearchHttpClient client = mock(SignedOpenSearchHttpClient.class);
        AnalysisRuntimeProperties properties = activeProperties();
        List<Float> vector = List.of(0.1f, 0.2f);
        when(embedding.embed(any())).thenReturn(vector);
        when(queryBuilder.build(eq("embedding"), eq("content"), eq(vector), eq(2))).thenReturn("knn-body");
        when(client.post(any(URI.class), eq("knn-body"), eq("aoss"))).thenReturn("response");
        List<ReferenceDocument> expected = List.of(new ReferenceDocument("ref-1", "title", "content", 1.0));
        when(parser.parse("response", "content")).thenReturn(expected);

        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(embedding, queryBuilder, parser, client, properties);
        assertThat(retriever.retrieve(query())).isEqualTo(expected);

        InOrder order = inOrder(embedding, queryBuilder, client, parser);
        order.verify(embedding).embed(any());
        order.verify(queryBuilder).build("embedding", "content", vector, 2);
        order.verify(client).post(URI.create("https://search.example/references/_search"), "knn-body", "aoss");
        order.verify(parser).parse("response", "content");
    }

    @Test
    void rejectsInvalidActiveConfigurationBeforeCallingDependencies() {
        AnalysisRuntimeProperties properties = activeProperties();
        properties.setOpensearchTopK(0);
        OpenSearchReferenceRetriever retriever = new OpenSearchReferenceRetriever(
                mock(EmbeddingProvider.class), mock(OpenSearchKnnQueryBuilder.class), mock(OpenSearchResponseParser.class),
                mock(SignedOpenSearchHttpClient.class), properties);
        assertThatThrownBy(() -> retriever.retrieve(query())).hasMessageContaining("top-k must be positive");
    }

    private AnalysisRuntimeProperties activeProperties() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockEmbeddingModelId("embedding-model");
        properties.setOpensearchEndpoint("https://search.example");
        properties.setIndexName("references");
        properties.setVectorFieldName("embedding");
        properties.setContentFieldName("content");
        properties.setOpensearchServiceName("aoss");
        properties.setOpensearchTopK(2);
        return properties;
    }

    private ReferenceQuery query() {
        return new ReferenceQuery("VPC private subnet to RDS", 2);
    }
}
