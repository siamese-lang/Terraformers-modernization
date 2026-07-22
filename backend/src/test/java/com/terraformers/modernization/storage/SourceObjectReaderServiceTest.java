package com.terraformers.modernization.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;

class SourceObjectReaderServiceTest {

    @Test
    void s3ReaderModeHeadsPersistedSourceArtifact() {
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ProjectFileEntity sourceFile = persistedSourceFile();
        S3Client s3Client = mock(S3Client.class);
        Instant lastModified = Instant.parse("2026-07-15T00:00:00Z");
        when(artifactService.requireLatestJobSourceImage(42L)).thenReturn(sourceFile);
        when(s3Client.headObject(any(HeadObjectRequest.class)))
                .thenReturn(HeadObjectResponse.builder()
                        .eTag("\"etag-from-s3\"")
                        .contentLength(16L)
                        .contentType("image/png")
                        .lastModified(lastModified)
                        .build());
        SourceObjectReaderService service = new SourceObjectReaderService(
                projectDomainService,
                artifactService,
                true,
                () -> s3Client,
                new StubObjectReader()
        );

        SourceObjectReadResponse response = service.read(42L, null);

        verify(projectDomainService).requireAccessibleProject(42L, null);
        ArgumentCaptor<HeadObjectRequest> requestCaptor = ArgumentCaptor.forClass(HeadObjectRequest.class);
        verify(s3Client).headObject(requestCaptor.capture());
        HeadObjectRequest request = requestCaptor.getValue();
        assertThat(request.bucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(request.key()).isEqualTo("browser-uploads/42/source.png");
        assertThat(response.projectId()).isEqualTo(42L);
        assertThat(response.sourceFileId()).isEqualTo(100L);
        assertThat(response.sourceBucket()).isEqualTo("terraformers-upload-bucket");
        assertThat(response.sourceKey()).isEqualTo("browser-uploads/42/source.png");
        assertThat(response.storageProvider()).isEqualTo("s3");
        assertThat(response.binaryPersisted()).isTrue();
        assertThat(response.sourceETag()).isEqualTo("\"etag-from-upload\"");
        assertThat(response.s3ETag()).isEqualTo("\"etag-from-s3\"");
        assertThat(response.contentLength()).isEqualTo(16L);
        assertThat(response.contentType()).isEqualTo("image/png");
        assertThat(response.lastModified()).isEqualTo(lastModified);
    }

    @Test
    void metadataOnlySourceArtifactIsRejectedBeforeS3Read() {
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ProjectFileEntity sourceFile = metadataOnlySourceFile();
        S3Client s3Client = mock(S3Client.class);
        when(artifactService.requireLatestJobSourceImage(42L)).thenReturn(sourceFile);
        SourceObjectReaderService service = new SourceObjectReaderService(
                projectDomainService,
                artifactService,
                true,
                () -> s3Client,
                new StubObjectReader()
        );

        assertThatThrownBy(() -> service.read(42L, null))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(exception -> ((ResponseStatusException) exception).getStatusCode())
                .isEqualTo(HttpStatus.CONFLICT);
        verify(s3Client, never()).headObject(any(HeadObjectRequest.class));
    }

    @Test
    void disabledReaderIsRejectedBeforeS3Read() {
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ProjectFileEntity sourceFile = persistedSourceFile();
        S3Client s3Client = mock(S3Client.class);
        when(artifactService.requireLatestJobSourceImage(42L)).thenReturn(sourceFile);
        SourceObjectReaderService service = new SourceObjectReaderService(
                projectDomainService,
                artifactService,
                false,
                () -> s3Client,
                new StubObjectReader()
        );

        assertThatThrownBy(() -> service.read(42L, null))
                .isInstanceOf(ResponseStatusException.class)
                .extracting(exception -> ((ResponseStatusException) exception).getStatusCode())
                .isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        verify(s3Client, never()).headObject(any(HeadObjectRequest.class));
    }

    @Test
    void sourceImageContentReturnsActualBytesAndContentType() {
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ProjectFileEntity sourceFile = persistedSourceFile();
        ObjectReader objectReader = mock(ObjectReader.class);
        byte[] bytes = new byte[] {1, 2, 3, 4};
        when(artifactService.requireLatestJobSourceImage(42L)).thenReturn(sourceFile);
        when(objectReader.readContent(new ObjectReference("terraformers-upload-bucket", "browser-uploads/42/source.png")))
                .thenReturn(new ObjectContent(
                        new ObjectMetadata("terraformers-upload-bucket", "browser-uploads/42/source.png", "image/png", bytes.length, "\"etag\""),
                        bytes
                ));
        SourceObjectReaderService service = new SourceObjectReaderService(
                projectDomainService,
                artifactService,
                true,
                () -> mock(S3Client.class),
                objectReader
        );

        ResponseEntity<byte[]> response = service.readImageContent(42L, null);

        verify(projectDomainService).requireAccessibleProject(42L, null);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getHeaders().getContentType().toString()).isEqualTo("image/png");
        assertThat(response.getHeaders().getContentLength()).isEqualTo(bytes.length);
        assertThat(response.getHeaders().getCacheControl()).contains("no-store");
        assertThat(response.getBody()).containsExactly(bytes);
    }

    @Test
    void sourceImageContentRequiresProjectAccessBeforeObjectRead() {
        ProjectDomainService projectDomainService = mock(ProjectDomainService.class);
        ProjectArtifactService artifactService = mock(ProjectArtifactService.class);
        ObjectReader objectReader = mock(ObjectReader.class);
        UserEntity requester = mock(UserEntity.class);
        org.mockito.Mockito.doThrow(new SecurityException("forbidden"))
                .when(projectDomainService).requireAccessibleProject(42L, requester);
        SourceObjectReaderService service = new SourceObjectReaderService(
                projectDomainService,
                artifactService,
                true,
                () -> mock(S3Client.class),
                objectReader
        );

        assertThatThrownBy(() -> service.readImageContent(42L, requester))
                .isInstanceOf(SecurityException.class)
                .hasMessage("forbidden");
        verify(artifactService, never()).requireLatestJobSourceImage(42L);
        verify(objectReader, never()).readContent(any(ObjectReference.class));
    }

    private ProjectFileEntity persistedSourceFile() {
        ProjectFileEntity file = mock(ProjectFileEntity.class);
        when(file.getFileId()).thenReturn(100L);
        when(file.getS3Bucket()).thenReturn("terraformers-upload-bucket");
        when(file.getS3Key()).thenReturn("browser-uploads/42/source.png");
        when(file.getStorageProvider()).thenReturn("s3");
        when(file.isBinaryPersisted()).thenReturn(true);
        when(file.getStorageETag()).thenReturn("\"etag-from-upload\"");
        return file;
    }

    private ProjectFileEntity metadataOnlySourceFile() {
        ProjectFileEntity file = mock(ProjectFileEntity.class);
        when(file.getFileId()).thenReturn(101L);
        when(file.getS3Bucket()).thenReturn("example-bucket");
        when(file.getS3Key()).thenReturn("browser-uploads/42/source.png");
        when(file.getStorageProvider()).thenReturn("metadata-only");
        when(file.isBinaryPersisted()).thenReturn(false);
        return file;
    }
}
