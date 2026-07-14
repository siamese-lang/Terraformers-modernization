package com.terraformers.modernization.analysis;

import java.net.URI;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api")
public class AnalysisUploadController {

    private static final DateTimeFormatter DATE_PATH = DateTimeFormatter.ofPattern("yyyy/MM/dd")
            .withZone(ZoneOffset.UTC);

    private final AnalysisJobService analysisJobService;
    private final String sourceBucket;
    private final String sourcePrefix;

    public AnalysisUploadController(
            AnalysisJobService analysisJobService,
            @Value("${terraformers.upload.source-bucket:example-bucket}") String sourceBucket,
            @Value("${terraformers.upload.source-prefix:browser-uploads}") String sourcePrefix
    ) {
        this.analysisJobService = analysisJobService;
        this.sourceBucket = sourceBucket;
        this.sourcePrefix = sourcePrefix;
    }

    @PostMapping(path = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<AnalysisUploadResponse> upload(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "projectId", required = false) String requestedProjectId
    ) {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("file must not be empty");
        }

        String originalFilename = safeOriginalFilename(file);
        String projectId = normalizeProjectId(requestedProjectId, originalFilename);
        String sourceKey = buildSourceKey(projectId, originalFilename);

        AnalysisJobResponse job = analysisJobService.create(new AnalysisJobRequest(
                projectId,
                sourceBucket,
                sourceKey,
                "upload-compat-" + System.currentTimeMillis()
        ));

        AnalysisUploadResponse response = AnalysisUploadResponse.from(
                job,
                originalFilename,
                resolveContentType(file),
                file.getSize()
        );

        return ResponseEntity
                .created(URI.create("/api/analysis/jobs/" + job.id()))
                .body(response);
    }

    private String buildSourceKey(String projectId, String originalFilename) {
        String prefix = normalizePrefix(sourcePrefix);
        String datePath = DATE_PATH.format(Instant.now());
        return prefix + "/" + projectId + "/" + datePath + "/" + System.currentTimeMillis() + "-" + sanitizeFilename(originalFilename);
    }

    private String normalizeProjectId(String requestedProjectId, String originalFilename) {
        String source = requestedProjectId;
        if (source == null || source.isBlank()) {
            source = stripExtension(originalFilename);
        }
        String normalized = source.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9-]+", "-")
                .replaceAll("^-+|-+$", "");
        if (normalized.isBlank()) {
            normalized = "browser-upload";
        }
        return normalized.length() > 64 ? normalized.substring(0, 64) : normalized;
    }

    private String safeOriginalFilename(MultipartFile file) {
        String originalFilename = file.getOriginalFilename();
        if (originalFilename == null || originalFilename.isBlank()) {
            return "architecture-image.png";
        }
        return originalFilename.replace('\\', '/').substring(originalFilename.replace('\\', '/').lastIndexOf('/') + 1);
    }

    private String sanitizeFilename(String filename) {
        String sanitized = filename.replaceAll("[^a-zA-Z0-9._-]+", "-")
                .replaceAll("^-+|-+$", "");
        return sanitized.isBlank() ? "architecture-image.png" : sanitized;
    }

    private String stripExtension(String filename) {
        int dotIndex = filename.lastIndexOf('.');
        if (dotIndex <= 0) {
            return filename;
        }
        return filename.substring(0, dotIndex);
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

    private String resolveContentType(MultipartFile file) {
        String contentType = file.getContentType();
        return contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType;
    }
}
