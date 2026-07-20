package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectMetadata;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockArchitectureFactsExtractorTest {
    @Test
    void extractsFactsAndAcceptsJsonFence() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("```json\n{\"summary\":\"EKS workload\",\"components\":[\"EKS\",\"RDS\",\" \"],\"relationships\":[\"EKS connects to RDS\"],\"resourceTypes\":[\"aws_eks_cluster\"]}\n```"));
        ArchitectureRetrievalFacts facts = extractor(client).extract(source());
        assertThat(facts.summary()).isEqualTo("EKS workload");
        assertThat(facts.components()).containsExactly("EKS", "RDS");
        assertThat(facts.relationships()).containsExactly("EKS connects to RDS");
    }

    @Test
    void acceptsFenceVariantsAndCompactJson() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(
                response("```\n{\"summary\":\"bare fence\",\"components\":[\"EKS\"]}\n```"),
                response("```JSON\n{\"summary\":\"uppercase fence\",\"components\":[\"RDS\"]}\n```\nGenerated facts"),
                response("```json{\"summary\":\"compact {facts}\",\"components\":[\"S3\"]}```"));

        assertThat(extractor(client).extract(source()).summary()).isEqualTo("bare fence");
        assertThat(extractor(client).extract(source()).summary()).isEqualTo("uppercase fence");
        assertThat(extractor(client).extract(source()).summary()).isEqualTo("compact {facts}");
    }

    @Test
    void requestsBoundedFactsWithEnoughOutputBudget() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"summary\":\"x\",\"components\":[\"EKS\"]}"));

        extractor(client).extract(source());

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(captor.capture());
        JsonNode request = new ObjectMapper().readTree(captor.getValue().body().asUtf8String());
        assertThat(request.path("max_tokens").asInt()).isEqualTo(800);
        String prompt = request.path("messages").path(0).path("content").path(1).path("text").asText();
        assertThat(prompt).contains("at most 8 strings", "under 60 characters");
    }

    @Test
    void rejectsInvalidCollectionsAndEmptyFactsWithoutLeakingPayload() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"summary\":\"x\",\"components\":\"EKS\"}"));
        assertThatThrownBy(() -> extractor(client).extract(source())).hasMessageNotContaining("SENTINEL_IMAGE");
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"summary\":\"x\",\"components\":[1]}"));
        assertThatThrownBy(() -> extractor(client).extract(source())).hasMessageNotContaining("SENTINEL_IMAGE");
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(response("{\"summary\":\"\",\"components\":[],\"relationships\":[],\"resourceTypes\":[]}"));
        assertThatThrownBy(() -> extractor(client).extract(source())).hasMessageNotContaining("SENTINEL_IMAGE");
    }

    private BedrockArchitectureFactsExtractor extractor(BedrockRuntimeClient client) {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("model");
        return new BedrockArchitectureFactsExtractor(client, new ObjectMapper(), properties);
    }
    private ObjectContent source() { return new ObjectContent(new ObjectMetadata("bucket", "key", "image/png", 14, "etag"), "SENTINEL_IMAGE".getBytes()); }
    private InvokeModelResponse response(String facts) throws Exception { return InvokeModelResponse.builder().body(SdkBytes.fromUtf8String(new ObjectMapper().writeValueAsString(java.util.Map.of("content", java.util.List.of(java.util.Map.of("type", "text", "text", facts)))))).build(); }
}
