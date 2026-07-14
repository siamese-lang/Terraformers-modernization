package com.terraformers.modernization.storage;

import java.nio.charset.StandardCharsets;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.storage", name = "s3-reader-enabled", havingValue = "false", matchIfMissing = true)
public class StubObjectReader implements ObjectReader {

    @Override
    public ObjectMetadata readMetadata(ObjectReference reference) {
        String contentType = inferContentType(reference.key());
        return new ObjectMetadata(
                reference.bucket(),
                reference.key(),
                contentType,
                0L,
                "stub-etag"
        );
    }

    @Override
    public ObjectContent readContent(ObjectReference reference) {
        ObjectMetadata metadata = readMetadata(reference);
        byte[] bytes = ("stub object content for s3://" + reference.bucket() + "/" + reference.key())
                .getBytes(StandardCharsets.UTF_8);
        return new ObjectContent(metadata, bytes);
    }

    private String inferContentType(String key) {
        String lower = key == null ? "" : key.toLowerCase();
        if (lower.endsWith(".png")) {
            return "image/png";
        }
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
            return "image/jpeg";
        }
        if (lower.endsWith(".webp")) {
            return "image/webp";
        }
        if (lower.endsWith(".gif")) {
            return "image/gif";
        }
        return "application/octet-stream";
    }
}
