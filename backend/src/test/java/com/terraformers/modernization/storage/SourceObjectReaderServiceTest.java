package com.terraformers.modernization.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.project.ProjectEntity;
import com.terraformers.modernization.project.ProjectRepository;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;

class SourceObjectReaderServiceTest {

    @Test
    void s3ReaderModeHeadsPersistedSourceObject() {
        ProjectRepository repository = mock(ProjectRepository.class);
        S3Client s3Client = mock(S3Client.class);
        Instant lastModified = Instant.parse("2026-07-15T00:00:00Z");
        when(repository.findById("aws-diagram")).thenReturn(Optional.of(persistedProject()));
        when(s3Client.headObject(any(HeadObjectRequest.class)))
                .thenReturn(HeadObjectResponse.builder()
                        .eTag("\"etag-from-s3\"")
                        .contentLength(16L)
                        .contentType("image/png")
                        .lastModified(lastModified)
                        .build());
        SourceObjectReaderService service = new SourceObjectReaderService(repository, true, () -> s3Client);

        SourceObjectReadResponse response = service.read("aws-diagram");

        ArgumentCaptor<HeadObjectRequest> requestCaptor = ArgumentCaptor.forClass(HeadObjectRequest.class);
        verify(s3Client).headObject(requestCaptor.capture());
        HeadObjectRequest request = requestCaptor.getValue();
        assertThat(request.bucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(request.key()).isEqualTo("browser-uploads/aws-diagram/source.png");
        assertThat(response.projectId()).isEqualTo("aws-diagram");
        assertThat(response.sourceBucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(response.sourceKey()).isEqualTo("browser-uploads/aws-diagram/source.png");
        assertThat(response.storageProvider()).isEqualTo("s3");
        assertThat(response.binaryPersisted()).isTrue();
        assertThat(response.sourceETag()).isEqualTo("\"etag-from-upload\"");
        assertThat(response.s3ETag()).isEqualTo("\"etag-from-s3\"");
        assertThat(response.contentLength()).isEqualTo(16L);
        assertThat(response.contentType()).isEqualTo("image/png");
        assertThat(response.lastModified()).isEqualTo(lastModified);
    }

    @Test
    void metadataOnlyProjectIsRejectedBeforeS3Read() {
        ProjectRepository repository = mock(ProjectRepository.class);
        S3Client s3Client = mock(S3Client.class);
        when(repository.findById("metadata-only")).thenReturn(Optional.of(metadataOnlyProject()));
        SourceObjectReaderService service = new SourceObjectReaderService(repository, true, () -> s3Client);

        assertThatThrownBy(() -> service.read("metadata-only"))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(exception -> ((ResponseStatusException) exception).getStatusCode())
                .isEqualTo(HttpStatus.CONFLICT);
        verify(s3Client, never()).headObject(any(HeadObjectRequest.class));
    }

    @Test
    void disabledReaderIsRejectedBeforeS3Read() {
        ProjectRepository repository = mock(ProjectRepository.class);
        S3Client s3Client = mock(S3Client.class);
        when(repository.findById("aws-diagram")).thenReturn(Optional.of(persistedProject()));
        SourceObjectReaderService service = new SourceObjectReaderService(repository, false, () -> s3Client);

        assertThatThrownBy(() -> service.read("aws-diagram"))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(exception -> ((ResponseStatusException) exception).getStatusCode())
                .isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        verify(s3Client, never()).headObject(any(HeadObjectRequest.class));
    }

    private ProjectEntity persistedProject() {
        ProjectEntity entity = new ProjectEntity();
        entity.setProjectId("aws-diagram");
        entity.setDisplayName("AWS Diagram");
        entity.setSourceBucket("terraformers-upload-bucket");
        entity.setSourceKey("browser-uploads/aws-diagram/source.png");
        entity.setSourceStorageProvider("s3");
        entity.setSourceBinaryPersisted(true);
        entity.setSourceETag("\"etag-from-upload\"");
        return entity;
    }

    private ProjectEntity metadataOnlyProject() {
        ProjectEntity entity = new ProjectEntity();
        entity.setProjectId("metadata-only");
        entity.setDisplayName("Metadata Only");
        entity.setSourceBucket("example-bucket");
        entity.setSourceKey("browser-uploads/metadata-only/source.png");
        entity.setSourceStorageProvider("metadata-only");
        entity.setSourceBinaryPersisted(false);
        return entity;
    }
}
