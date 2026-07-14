package com.terraformers.modernization.storage;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class StubObjectWriterTest {

    @Test
    void returnsRequestedObjectLocationWithoutAwsCredentials() {
        StubObjectWriter writer = new StubObjectWriter();

        ObjectWriteResult result = writer.writeText(new ObjectWriteRequest(
                "example-bucket",
                "analysis-results/project-1/job-1/main.tf",
                "provider \"aws\" {}",
                "text/plain; charset=utf-8"
        ));

        assertThat(result.bucket()).isEqualTo("example-bucket");
        assertThat(result.key()).isEqualTo("analysis-results/project-1/job-1/main.tf");
        assertThat(result.objectUri()).isEqualTo("s3://example-bucket/analysis-results/project-1/job-1/main.tf");
        assertThat(result.eTag()).isEqualTo("stub-etag");
    }
}
