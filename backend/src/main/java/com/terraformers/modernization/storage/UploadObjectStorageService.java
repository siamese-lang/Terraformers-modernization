package com.terraformers.modernization.storage;

import java.io.IOException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.function.Supplier;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;

@Service
public class UploadObjectStorageService {

    private static final DateTimeFormatter DATE_PATH = DateTimeFormatter.ofPattern("yyyy/MM/dd")
            .withZone(ZoneOffset.UTC);

    private final boolean s3WriterEnabled;
    private final String sourceBucket;
    private final String sourcePrefix;
    private final Supplier<S3Client> s3ClientSupplier;

    @Autowired
    public UploadObjectStorageService(
            ObjectProvider<S3Client> s3ClientProvider,
            @Value("${terraformers.storage.s3-writer-enabled:false}") boolean s3WriterEnabled,
            @Value("${terraformers.upload.source-bucket:example-bucket}") String sourceBucket,
            @Value("${terraformers.upload.source-prefix:browser-uploads}") String sourcePrefix
    ) {
        this(
                s3WriterEnabled,
                sourceBucket,
                sourcePrefix,
                () -> s3ClientProvider.getIfAvailable(S3Client::create)
        );
    }

    UploadObjectStorageService(
            boolean s3WriterEnabled,
            String sourceBucket,
            String sourcePrefix,
            Supplier<S3Client> s3ClientSupplier
    ) {
        this.s3WriterEnabled = s3WriterEnabled;
        this.sourceBucket = normalizeBucket(sourceBucket);
        this.sourcePrefix = normalizePrefix(sourcePrefix);
        this.s3ClientSupplier = s3ClientSupplier;
    }

    public StoredUploadObject store(MultipartFile file, String projectId, String originalFilename) {
        String sourceKey = buildSourceKey(projectId, originalFilename);

        if (!s3WriterEnabled) {
            return StoredUploadObject.metadataOnly(sourceBucket, sourceKey);
        }

        try {
            PutObjectRequest request = PutObjectRequest.builder()
                    .bucket(sourceBucket)
                    .key(sourceKey)
                    .contentType(resolveContentType(file))
                    .contentLength(file.getSize())
                    .build();
            PutObjectResponse response = s3ClientSupplier.get().putObject(
                    request,
                    RequestBody.fromInputStream(file.getInputStream(), file.getSize())
            );
            return StoredUploadObject.s3(sourceBucket, sourceKey, response.eTag());
        } catch (IOException | RuntimeException exception) {
            throw new UploadStorageException("failed to persist upload object: " + sourceKey, exception);
        }
    }

    private String buildSourceKey(String projectId, String originalFilename) {
        String datePath = DATE_PATH.format(Instant.now());
        return sourcePrefix + "/" + projectId + "/" + datePath + "/" + System.currentTimeMillis() + "-" + sanitizeFilename(originalFilename);
    }

    private String normalizeBucket(String bucket) {
        if (bucket == null || bucket.isBlank()) {
            return "example-bucket";
        }
        return bucket.strip();
    }

    private String normalizePrefix(String prefix) {
        if (prefix == null || prefix.isBlank()) {
            return "browser-uploads";
        }
        String normalized = prefix.strip();
        while (normalized.startsWith("/")) {
            normalized = normalized.substring(1);
        }
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized.isBlank() ? "browser-uploads" : normalized;
    }

    private String sanitizeFilename(String filename) {
        String sanitized = filename.replaceAll("[^a-zA-Z0-9._-]+", "-")
                .replaceAll("^-+|-+$", "");
        return sanitized.isBlank() ? "architecture-image.png" : sanitized;
    }

    private String resolveContentType(MultipartFile file) {
        String contentType = file.getContentType();
        return contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType;
    }
}
