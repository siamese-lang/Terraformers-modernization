package com.terraformers.modernization.storage;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import java.util.function.Supplier;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.S3Exception;

@Service
public class SourceObjectReaderService {

    private final ProjectDomainService projectDomainService;
    private final ProjectArtifactService projectArtifactService;
    private final boolean s3ReaderEnabled;
    private final Supplier<S3Client> s3ClientSupplier;
    private final ObjectReader objectReader;

    @Autowired
    public SourceObjectReaderService(
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            ObjectProvider<S3Client> s3ClientProvider,
            ObjectReader objectReader,
            @Value("${terraformers.storage.s3-reader-enabled:false}") boolean s3ReaderEnabled
    ) {
        this(
                projectDomainService,
                projectArtifactService,
                s3ReaderEnabled,
                () -> s3ClientProvider.getIfAvailable(S3Client::create),
                objectReader
        );
    }

    SourceObjectReaderService(
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            boolean s3ReaderEnabled,
            Supplier<S3Client> s3ClientSupplier,
            ObjectReader objectReader
    ) {
        this.projectDomainService = projectDomainService;
        this.projectArtifactService = projectArtifactService;
        this.s3ReaderEnabled = s3ReaderEnabled;
        this.s3ClientSupplier = s3ClientSupplier;
        this.objectReader = objectReader;
    }

    @Transactional(readOnly = true)
    public SourceObjectReadResponse read(Long projectId, UserEntity currentUser) {
        projectDomainService.requireAccessibleProject(projectId, currentUser);
        ProjectFileEntity sourceFile = projectArtifactService.requireLatestSourceImage(projectId);

        if (!sourceFile.isBinaryPersisted()
                || isBlank(sourceFile.getS3Bucket())
                || isBlank(sourceFile.getS3Key())) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "project source object is metadata-only or missing: " + projectId
            );
        }

        if (!s3ReaderEnabled) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "s3 reader is disabled");
        }

        try {
            HeadObjectResponse head = s3ClientSupplier.get().headObject(HeadObjectRequest.builder()
                    .bucket(sourceFile.getS3Bucket())
                    .key(sourceFile.getS3Key())
                    .build());

            return new SourceObjectReadResponse(
                    projectId,
                    sourceFile.getFileId(),
                    sourceFile.getS3Bucket(),
                    sourceFile.getS3Key(),
                    sourceFile.getStorageProvider(),
                    sourceFile.isBinaryPersisted(),
                    sourceFile.getStorageETag(),
                    head.eTag(),
                    head.contentLength(),
                    head.contentType(),
                    head.lastModified()
            );
        } catch (S3Exception exception) {
            if (exception.statusCode() == 404) {
                throw new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "source object not found in S3: " + sourceFile.getS3Key(),
                        exception
                );
            }
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "failed to read source object metadata: " + sourceFile.getS3Key(),
                    exception
            );
        }
    }

    @Transactional(readOnly = true)
    public ResponseEntity<byte[]> readImageContent(Long projectId, UserEntity currentUser) {
        projectDomainService.requireAccessibleProject(projectId, currentUser);
        ProjectFileEntity sourceFile = projectArtifactService.requireLatestSourceImage(projectId);
        if (!sourceFile.isBinaryPersisted() || isBlank(sourceFile.getS3Bucket()) || isBlank(sourceFile.getS3Key())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "project source image content is unavailable: " + projectId);
        }
        if (!s3ReaderEnabled) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "s3 reader is disabled");
        }
        ObjectContent content = objectReader.readContent(new ObjectReference(sourceFile.getS3Bucket(), sourceFile.getS3Key()));
        String contentType = content.metadata().contentType() == null ? sourceFile.getContentType() : content.metadata().contentType();
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .header(HttpHeaders.CONTENT_LENGTH, String.valueOf(content.size()))
                .contentType(MediaType.parseMediaType(contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType))
                .body(content.bytes());
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
