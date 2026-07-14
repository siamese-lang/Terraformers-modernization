package com.terraformers.modernization.storage;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class StubObjectReaderTest {

    private final StubObjectReader reader = new StubObjectReader();

    @Test
    void readsImageMetadataWithoutAwsCredentials() {
        ObjectMetadata metadata = reader.readMetadata(new ObjectReference("example-bucket", "uploads/diagram.png"));

        assertThat(metadata.bucket()).isEqualTo("example-bucket");
        assertThat(metadata.key()).isEqualTo("uploads/diagram.png");
        assertThat(metadata.contentType()).isEqualTo("image/png");
        assertThat(metadata.eTag()).isEqualTo("stub-etag");
    }

    @Test
    void readsStubContentWithoutAwsCredentials() {
        ObjectContent content = reader.readContent(new ObjectReference("example-bucket", "uploads/diagram.jpg"));

        assertThat(content.metadata().contentType()).isEqualTo("image/jpeg");
        assertThat(content.size()).isGreaterThan(0);
    }
}
