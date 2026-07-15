package com.terraformers.modernization.analysis;

import com.terraformers.modernization.project.ProjectMetadataService;
import com.terraformers.modernization.storage.StoredUploadObject;
import com.terraformers.modernization.storage.UploadObjectStorageService;
import com.terraformers.modernization.storage.UploadStorageException;
import java.net.URI;
import java.util.Locale;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api")
public class AnalysisUploadController {

    private final AnalysisJobService analysisJobService;
    private final ProjectMetadataService projectMetadataService;
    private final UploadObjectStorageService uploadObjectStorageService;

    public AnalysisUploadController(
            AnalysisJobService analysisJobService,
            ProjectMetadataService projectMetadataService,
            UploadObjectStorageService uploadObjectStorageService
    ) {
        this.analysisJobService = analysisJobService;
        this.projectMetadataService = projectMetadataService;
        this.uploadObjectStorageService = uploadObjectStorageService;
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
        StoredUploadObject storedUpload = uploadObjectStorageService.store(file, projectId, originalFilename);

        AnalysisJobResponse job = analysisJobService.create(new AnalysisJobRequest(
                projectId,
                storedUpload.bucket(),
                storedUpload.key(),
                "upload-compat-" + System.currentTimeMillis()
        ));

        AnalysisUploadResponse response = AnalysisUploadResponse.from(
                job,
                originalFilename,
                resolveContentType(file),
                file.getSize(),
                storedUpload
        );
        projectMetadataService.upsertFromUpload(response);

        return ResponseEntity
                .created(URI.create("/api/analysis/jobs/" + job.id()))
                .body(response);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBadUploadRequest(IllegalArgumentException exception) {
        return ResponseEntity.badRequest().body(exception.getMessage());
    }

    @ExceptionHandler(UploadStorageException.class)
    public ResponseEntity<String> handleUploadStorageFailure(UploadStorageException exception) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(exception.getMessage());
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
        String normalized = originalFilename.replace('\\', '/');
        return normalized.substring(normalized.lastIndexOf('/') + 1);
    }

    private String stripExtension(String filename) {
        int dotIndex = filename.lastIndexOf('.');
        if (dotIndex <= 0) {
            return filename;
        }
        return filename.substring(0, dotIndex);
    }

    private String resolveContentType(MultipartFile file) {
        String contentType = file.getContentType();
        return contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType;
    }
}
