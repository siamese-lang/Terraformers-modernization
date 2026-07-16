package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.UploadStorageException;
import java.net.URI;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api")
public class AnalysisUploadController {

    private final AnalysisUploadService uploadService;

    public AnalysisUploadController(AnalysisUploadService uploadService) {
        this.uploadService = uploadService;
    }

    @PostMapping(path = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<AnalysisUploadResponse> upload(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "projectId", required = false) Long requestedProjectId,
            @RequestParam(value = "projectName", required = false) String requestedProjectName,
            @AuthenticationPrincipal Jwt jwt
    ) {
        AnalysisUploadResponse response = uploadService.upload(
                file,
                requestedProjectId,
                requestedProjectName,
                jwt
        );
        return ResponseEntity
                .created(URI.create("/api/analysis/jobs/" + response.analysisJobId()))
                .body(response);
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<String> handleUnauthorized(AuthenticationException exception) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(exception.getMessage());
    }

    @ExceptionHandler(SecurityException.class)
    public ResponseEntity<String> handleForbidden(SecurityException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(exception.getMessage());
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<String> handleNotFound(NoSuchElementException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(exception.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<String> handleBadUploadRequest(IllegalArgumentException exception) {
        return ResponseEntity.badRequest().body(exception.getMessage());
    }

    @ExceptionHandler(UploadStorageException.class)
    public ResponseEntity<String> handleUploadStorageFailure(UploadStorageException exception) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(exception.getMessage());
    }
}
