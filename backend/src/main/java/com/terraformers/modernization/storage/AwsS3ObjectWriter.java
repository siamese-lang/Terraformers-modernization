package com.terraformers.modernization.storage;

import java.nio.charset.StandardCharsets;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectResponse;

@Component
@ConditionalOnProperty(prefix = "terraformers.storage", name = "s3-writer-enabled", havingValue = "true")
public class AwsS3ObjectWriter implements ObjectWriter {

    private final S3Client s3Client;

    public AwsS3ObjectWriter() {
        this.s3Client = S3Client.builder().build();
    }

    @Override
    public ObjectWriteResult writeText(ObjectWriteRequest request) {
        byte[] bytes = request.content().getBytes(StandardCharsets.UTF_8);
        PutObjectResponse response = s3Client.putObject(PutObjectRequest.builder()
                .bucket(request.bucket())
                .key(request.key())
                .contentType(request.contentType())
                .contentLength((long) bytes.length)
                .build(), RequestBody.fromBytes(bytes));

        return new ObjectWriteResult(request.bucket(), request.key(), response.eTag());
    }
}
