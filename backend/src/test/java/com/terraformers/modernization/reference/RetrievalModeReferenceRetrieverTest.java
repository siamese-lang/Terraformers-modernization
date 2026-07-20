package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.opensearch.OpenSearchReferenceRetriever;
import java.util.List;
import org.junit.jupiter.api.Test;

class RetrievalModeReferenceRetrieverTest {
    private final ReferenceQuery query = new ReferenceQuery("VPC private subnet to RDS", 3);

    @Test
    void requiredPropagatesVectorFailure() {
        OpenSearchReferenceRetriever vector = mock(OpenSearchReferenceRetriever.class);
        AnalysisRuntimeProperties properties = properties(RetrievalMode.REQUIRED);
        when(vector.retrieve(any())).thenThrow(new IllegalStateException("request failed"));
        assertThatThrownBy(() -> retriever(vector, properties).retrieve(query)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void requiredRejectsEmptyResults() {
        OpenSearchReferenceRetriever vector = mock(OpenSearchReferenceRetriever.class);
        when(vector.retrieve(any())).thenReturn(List.of());
        AnalysisRuntimeProperties properties = properties(RetrievalMode.REQUIRED);
        assertThatThrownBy(() -> retriever(vector, properties).retrieve(query)).hasMessageContaining("no documents");
    }

    @Test
    void optionalConvertsVectorFailureToEmptyReferences() {
        OpenSearchReferenceRetriever vector = mock(OpenSearchReferenceRetriever.class);
        when(vector.retrieve(any())).thenThrow(new IllegalStateException("request failed"));
        assertThat(retriever(vector, properties(RetrievalMode.OPTIONAL)).retrieve(query)).isEmpty();
    }

    @Test
    void optionalAllowsEmptyResults() {
        OpenSearchReferenceRetriever vector = mock(OpenSearchReferenceRetriever.class);
        when(vector.retrieve(any())).thenReturn(List.of());
        assertThat(retriever(vector, properties(RetrievalMode.OPTIONAL)).retrieve(query)).isEmpty();
    }

    @Test
    void disabledDoesNotCallVectorRetriever() {
        OpenSearchReferenceRetriever vector = mock(OpenSearchReferenceRetriever.class);
        assertThat(retriever(vector, properties(RetrievalMode.DISABLED)).retrieve(query)).isEmpty();
        verify(vector, never()).retrieve(any());
    }

    private RetrievalModeReferenceRetriever retriever(OpenSearchReferenceRetriever vector, AnalysisRuntimeProperties properties) {
        return new RetrievalModeReferenceRetriever(vector, properties);
    }

    private AnalysisRuntimeProperties properties(RetrievalMode mode) {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setRetrievalMode(mode);
        return properties;
    }
}
