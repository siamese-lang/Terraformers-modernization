package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
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

class BedrockRuntimeAnalysisProviderTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void invokesBedrockRuntimeWithSourceMetadataAndRetrievedReferences() throws Exception {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("""
                                {
                                  "content": [
                                    {"type": "text", "text": "resource \\\"aws_s3_bucket\\\" \\\"example\\\" {}"}
                                  ]
                                }
                                """))
                        .build());

        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("anthropic.claude-3-haiku-20240307-v1:0");
        properties.setBedrockMaxTokens(1024);

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties,
                objectReader(),
                referenceRetriever()
        );

        AnalysisResult result = provider.analyze(context());

        ArgumentCaptor<InvokeModelRequest> requestCaptor = ArgumentCaptor.forClass(InvokeModelRequest.class);
        verify(bedrockRuntimeClient).invokeModel(requestCaptor.capture());

        InvokeModelRequest request = requestCaptor.getValue();
        assertThat(request.modelId()).isEqualTo("anthropic.claude-3-haiku-20240307-v1:0");
        assertThat(request.contentType()).isEqualTo("application/json");
        assertThat(request.accept()).isEqualTo("application/json");

        JsonNode body = objectMapper.readTree(request.body().asUtf8String());
        assertThat(body.path("anthropic_version").asText()).isEqualTo("bedrock-2023-05-31");
        assertThat(body.path("max_tokens").asInt()).isEqualTo(1024);
        assertThat(body.path("messages").get(0).path("role").asText()).isEqualTo("user");
        assertThat(body.toString()).contains("projectId: project-123");
        assertThat(body.toString()).contains("sourceBucket: terraformers-source");
        assertThat(body.toString()).contains("sourceKey: browser-uploads/project-123/source.png");
        assertThat(body.toString()).contains("contentType: image/png");
        assertThat(body.toString()).contains("ref-vpc-s3");
        assertThat(body.toString()).contains("VPC and S3 Terraform reference");
        assertThat(body.toString()).contains("Keep public access blocked on S3 buckets");

        assertThat(result.provider()).isEqualTo("bedrock-runtime");
        assertThat(result.terraformCode()).isEqualTo("resource \"aws_s3_bucket\" \"example\" {}");
        assertThat(result.explanation()).contains("1 retrieved reference document");
        assertThat(result.references()).containsExactly(
                "s3://terraformers-source/browser-uploads/project-123/source.png",
                "ref-vpc-s3"
        );
    }

    @Test
    void missingModelIdFailsBeforeCallingBedrock() {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties,
                objectReader(),
                referenceRetriever()
        );

        assertThatThrownBy(() -> provider.analyze(context()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("bedrock-model-id");

        verify(bedrockRuntimeClient, never()).invokeModel(any(InvokeModelRequest.class));
    }

    @Test
    void supportsLegacyCompletionTextShape() {
        BedrockRuntimeClient bedrockRuntimeClient = mock(BedrockRuntimeClient.class);
        when(bedrockRuntimeClient.invokeModel(any(InvokeModelRequest.class)))
                .thenReturn(InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String("{\"completion\":\"terraform block\"}"))
                        .build());

        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();
        properties.setBedrockModelId("legacy-model");

        BedrockRuntimeAnalysisProvider provider = new BedrockRuntimeAnalysisProvider(
                bedrockRuntimeClient,
                objectMapper,
                properties,
                objectReader(),
                referenceRetriever()
        );

        AnalysisResult result = provider.analyze(context());

        assertThat(result.terraformCode()).isEqualTo("terraform block");
    }

    private ObjectReader objectReader() {
        return new ObjectReader() {
            @Override
            public ObjectMetadata readMetadata(ObjectReference reference) {
                return new ObjectMetadata(
                        reference.bucket(),
                        reference.key(),
                        "image/png",
                        2048L,
                        "etag-123"
                );
            }

            @Override
            public ObjectContent readContent(ObjectReference reference) {
                return new ObjectContent(
                        readMetadata(reference),
                        "image bytes".getBytes(StandardCharsets.UTF_8)
                );
            }
        };
    }

    private ReferenceRetriever referenceRetriever() {
        return new ReferenceRetriever() {
            @Override
            public List<ReferenceDocument> retrieve(ReferenceQuery query) {
                assertThat(query.projectId()).isEqualTo("project-123");
                assertThat(query.sourceBucket()).isEqualTo("terraformers-source");
                assertThat(query.sourceKey()).isEqualTo("browser-uploads/project-123/source.png");
                assertThat(query.contentType()).isEqualTo("image/png");
                return List.of(new ReferenceDocument(
                        "ref-vpc-s3",
                        "VPC and S3 Terraform reference",
                        "Keep public access blocked on S3 buckets and separate network boundaries.",
                        8.25
                ));
            }
        };
    }

    private AnalysisRequestContext context() {
        return new AnalysisRequestContext(
                "job-123",
                "project-123",
                "terraformers-source",
                "browser-uploads/project-123/source.png",
                "correlation-123",
                AnalysisMode.INTEGRATED_JAVA
        );
    }
}
