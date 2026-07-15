package com.terraformers.modernization.storage;

import com.terraformers.modernization.project.ProjectEntity;
import com.terraformers.modernization.project.ProjectRepository;
import java.util.NoSuchElementException;
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

    private final ProjectRepository repository;
    private final boolean s3ReaderEnabled;
    private final Supplier<S3Client> s3ClientSupplier;

    @Autowired
    public SourceObjectReaderService(
            ProjectRepository repository,
            ObjectProvider<S3Client> s3ClientProvider,
            @Value("${terraformers.storage.s3-reader-enabled:false}") boolean s3ReaderEnabled
    ) {
        this(
                repository,
                s3ReaderEnabled,
                () -> s3ClientProvider.getIfAvailable(S3Client::create)
        );
    }

    SourceObjectReaderService(
            ProjectRepository repository,
            boolean s3ReaderEnabled,
            Supplier<S3Client> s3ClientSupplier
    ) {
        this.repository = repository;
        this.s3ReaderEnabled = s3ReaderEnabled;
        this.s3ClientSupplier = s3ClientSupplier;
    }

    @Transactional(readOnly = true)
    public SourceObjectReadResponse read(String projectId) {
        ProjectEntity project = repository.findById(projectId)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));

        if (!project.isSourceBinaryPersisted() || isBlank(project.getSourceBucket()) || isBlank(project.getSourceKey())) {
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
                    .bucket(project.getSourceBucket())
                    .key(project.getSourceKey())
                    .build());

            return new SourceObjectReadResponse(
                    project.getProjectId(),
                    project.getSourceBucket(),
                    project.getSourceKey(),
                    project.getSourceStorageProvider(),
                    project.isSourceBinaryPersisted(),
                    project.getSourceETag(),
                    head.eTag(),
                    head.contentLength(),
                    head.contentType(),
                    head.lastModified()
            );
        } catch (S3Exception exception) {
            if (exception.statusCode() == 404) {
                throw new ResponseStatusException(
                        HttpStatus.NOT_FOUND,
                        "source object not found in S3: " + project.getSourceKey(),
                        exception
                );
            }
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "failed to read source object metadata: " + project.getSourceKey(),
                    exception
            );
        }
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
