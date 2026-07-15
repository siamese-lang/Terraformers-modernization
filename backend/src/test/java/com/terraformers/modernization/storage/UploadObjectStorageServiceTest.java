package com.terraformers.modernization.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockMultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;

class UploadObjectStorageServiceTest {

    @Test
    void metadataOnlyModeReturnsSourceReferenceWithoutS3Put() {
        S3Client s3Client = mock(S3Client.class);
        UploadObjectStorageService service = new UploadObjectStorageService(
                false,
                "example-bucket",
                "/browser-uploads/",
                () -> s3Client
        );

        StoredUploadObject result = service.store(imageFile(), "aws", "AWS아키텍처.png");

        assertThat(result.provider()).isEqualTo("metadata-only");
        assertThat(result.binaryPersisted()).isFalse();
        assertThat(result.bucket()).isEqualTo("example-bucket");
        assertThat(result.key()).startsWith("browser-uploads/aws/");
        assertThat(result.key()).endsWith("AWS-.png");
        assertThat(result.eTag()).isNull();
        verify(s3Client, never()).putObject(any(PutObjectRequest.class), any(RequestBody.class));
    }

    @Test
    void s3WriterModePutsObjectAndReturnsPersistedReference() {
        S3Client s3Client = mock(S3Client.class);
        when(s3Client.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
                .thenReturn(PutObjectResponse.builder().eTag("\"etag-123\"").build());
        UploadObjectStorageService service = new UploadObjectStorageService(
                true,
                "terraformers-upload-bucket",
                "browser-uploads",
                () -> s3Client
        );

        StoredUploadObject result = service.store(imageFile(), "aws", "AWS아키텍처.png");

        ArgumentCaptor<PutObjectRequest> requestCaptor = ArgumentCaptor.forClass(PutObjectRequest.class);
        verify(s3Client).putObject(requestCaptor.capture(), any(RequestBody.class));

        PutObjectRequest request = requestCaptor.getValue();
        assertThat(request.bucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(request.key()).startsWith("browser-uploads/aws/");
        assertThat(request.contentType()).isEqualTo("image/png");
        assertThat(request.contentLength()).isEqualTo(16);
        assertThat(result.provider()).isEqualTo("s3");
        assertThat(result.binaryPersisted()).isTrue();
        assertThat(result.bucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(result.key()).isEqualTo(request.key());
        assertThat(result.eTag()).isEqualTo("\"etag-123\"");
    }

    private MockMultipartFile imageFile() {
        return new MockMultipartFile(
                "file",
                "AWS아키텍처.png",
                "image/png",
                "fake image bytes".getBytes()
        );
    }
}
