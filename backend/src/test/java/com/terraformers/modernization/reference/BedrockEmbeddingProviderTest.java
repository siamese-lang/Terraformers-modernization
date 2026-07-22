package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockEmbeddingProviderTest {
    @Test
    void rejectsMissingOrEmptyEmbeddingArraysAndDimensionMismatch() {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        AnalysisRuntimeProperties properties = properties();
        BedrockEmbeddingProvider provider = new BedrockEmbeddingProvider(client, new ObjectMapper(), properties);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{}"));
        assertThatThrownBy(() -> provider.embed("sentinel prompt")).hasMessageContaining("failed to generate");
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"embedding\":[]}"));
        assertThatThrownBy(() -> provider.embed("sentinel prompt")).hasMessageContaining("failed to generate");
        properties.setExpectedVectorDimension(3);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"embedding\":[1,2]}"));
        assertThatThrownBy(() -> provider.embed("sentinel prompt")).hasMessageContaining("failed to generate");
    }

    @Test
    void wrapsBedrockInvocationFailureWithoutEmbeddingInput() {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenThrow(new IllegalStateException("unavailable"));
        assertThatThrownBy(() -> new BedrockEmbeddingProvider(client, new ObjectMapper(), properties()).embed("sentinel prompt"))
                .hasMessageNotContaining("sentinel prompt");
    }

    private AnalysisRuntimeProperties properties() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockEmbeddingModelId("embedding-model");
        return properties;
    }

    private InvokeModelResponse response(String body) {
        return InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(body)).build();
    }
}
