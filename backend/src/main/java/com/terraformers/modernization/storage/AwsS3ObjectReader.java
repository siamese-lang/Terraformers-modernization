package com.terraformers.modernization.storage;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;

@Component
@ConditionalOnProperty(prefix = "terraformers.storage", name = "s3-reader-enabled", havingValue = "true")
public class AwsS3ObjectReader implements ObjectReader {

    private final S3Client s3Client;

    public AwsS3ObjectReader() {
        this.s3Client = S3Client.builder().build();
    }

    @Override
    public ObjectMetadata readMetadata(ObjectReference reference) {
        HeadObjectResponse response = s3Client.headObject(HeadObjectRequest.builder()
                .bucket(reference.bucket())
                .key(reference.key())
                .build());

        return new ObjectMetadata(
                reference.bucket(),
                reference.key(),
                response.contentType(),
                response.contentLength(),
                response.eTag()
        );
    }

    @Override
    public ObjectContent readContent(ObjectReference reference) {
        ResponseBytes<GetObjectResponse> response = s3Client.getObjectAsBytes(GetObjectRequest.builder()
                .bucket(reference.bucket())
                .key(reference.key())
                .build());

        ObjectMetadata metadata = new ObjectMetadata(
                reference.bucket(),
                reference.key(),
                response.response().contentType(),
                response.response().contentLength(),
                response.response().eTag()
        );

        return new ObjectContent(metadata, response.asByteArray());
    }
}
