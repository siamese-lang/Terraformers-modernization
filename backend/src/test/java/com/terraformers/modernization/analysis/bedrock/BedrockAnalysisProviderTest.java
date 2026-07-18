package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.analysis.AnalysisMode;
import com.terraformers.modernization.analysis.AnalysisRequestContext;
import com.terraformers.modernization.analysis.AnalysisResult;
import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.storage.ObjectContent;
import com.terraformers.modernization.storage.ObjectMetadata;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

class BedrockAnalysisProviderTest {
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void invokesConfiguredModelWithImageBytesAndStructuredJsonSchema() throws Exception {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(InvokeModelResponse.builder()
                .body(SdkBytes.fromUtf8String("""
                        {"content":[{"type":"text","text":"{\"summary\":\"Private web stack\",\"components\":[\"VPC\",\"ALB\"],\"relationships\":[\"ALB forwards to service\"],\"warnings\":[],\"terraformCode\":\"resource \\\"aws_vpc\\\" \\\"main\\\" { cidr_block = \\\"10.0.0.0/16\\\" }\"}"}]}
                        """))
                .build());
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("configured-model-id");
        properties.setBedrockMaxTokens(2048);

        BedrockAnalysisProvider provider = new BedrockAnalysisProvider(
                client,
                objectReader(),
                referenceRetriever(),
                properties,
                new BedrockPromptBuilder(objectMapper),
                new BedrockResponseParser(objectMapper)
        );

        AnalysisResult result = provider.analyze(context());

        ArgumentCaptor<InvokeModelRequest> captor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(client).invokeModel(captor.capture());
        InvokeModelRequest request = captor.getValue();
        assertThat(request.modelId()).isEqualTo("configured-model-id");
        JsonNode body = objectMapper.readTree(request.body().asUtf8String());
        assertThat(body.path("messages").get(0).path("content").get(0).path("type").asText()).isEqualTo("image");
        assertThat(body.toString()).contains("terraformCode");
        assertThat(body.toString()).contains("Return JSON only");
        assertThat(result.explanation()).isEqualTo("Private web stack");
        assertThat(result.components()).containsExactly("VPC", "ALB");
        assertThat(result.relationships()).containsExactly("ALB forwards to service");
        assertThat(result.terraformCode()).contains("resource \"aws_vpc\"");
    }

    private ObjectReader objectReader() {
        return new ObjectReader() {
            @Override
            public ObjectMetadata readMetadata(ObjectReference reference) {
                return metadata(reference);
            }

            @Override
            public ObjectContent readContent(ObjectReference reference) {
                return new ObjectContent(metadata(reference), "image bytes".getBytes(StandardCharsets.UTF_8));
            }

            private ObjectMetadata metadata(ObjectReference reference) {
                return new ObjectMetadata(reference.bucket(), reference.key(), "image/png", 11L, "etag");
            }
        };
    }

    private ReferenceRetriever referenceRetriever() {
        return query -> List.of(new ReferenceDocument("ref-1", "Reference", "Use private subnets", 1.0));
    }

    private AnalysisRequestContext context() {
        return new AnalysisRequestContext("job", "project", "bucket", "key.png", "corr", AnalysisMode.INTEGRATED_JAVA);
    }
}
