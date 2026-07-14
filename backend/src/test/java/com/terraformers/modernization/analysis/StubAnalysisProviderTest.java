package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.reference.StubReferenceRetriever;
import com.terraformers.modernization.storage.StubObjectReader;
import org.junit.jupiter.api.Test;

class StubAnalysisProviderTest {

    @Test
    void usesObjectReaderMetadataAndReferenceRetrieverInExplanation() {
        StubAnalysisProvider provider = new StubAnalysisProvider(
                new StubObjectReader(),
                new StubReferenceRetriever()
        );
        AnalysisRequestContext context = new AnalysisRequestContext(
                "job-1",
                "project-1",
                "example-bucket",
                "uploads/diagram.webp",
                "corr-1",
                AnalysisMode.INTEGRATED_JAVA
        );

        AnalysisResult result = provider.analyze(context);

        assertThat(result.provider()).isEqualTo("stub-integrated-java");
        assertThat(result.explanation()).contains("s3://example-bucket/uploads/diagram.webp");
        assertThat(result.explanation()).contains("contentType=image/webp");
        assertThat(result.explanation()).contains("references=2");
        assertThat(result.references()).contains("stub-vpc-rds-s3", "stub-sqs-async");
        assertThat(result.terraformCode()).contains("provider \"aws\"");
    }
}
