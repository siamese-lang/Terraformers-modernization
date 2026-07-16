package com.terraformers.modernization.storage;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import java.util.function.Supplier;
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

    @Autowired
    public SourceObjectReaderService(
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            ObjectProvider<S3Client> s3ClientProvider,
            @Value("${terraformers.storage.s3-reader-enabled:false}") boolean s3ReaderEnabled
    ) {
        this(
                projectDomainService,
                projectArtifactService,
                s3ReaderEnabled,
                () -> s3ClientProvider.getIfAvailable(S3Client::create)
        );
    }

    SourceObjectReaderService(
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            boolean s3ReaderEnabled,
            Supplier<S3Client> s3ClientSupplier
    ) {
        this.projectDomainService = projectDomainService;
        this.projectArtifactService = projectArtifactService;
        this.s3ReaderEnabled = s3ReaderEnabled;
        this.s3ClientSupplier = s3ClientSupplier;
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

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
