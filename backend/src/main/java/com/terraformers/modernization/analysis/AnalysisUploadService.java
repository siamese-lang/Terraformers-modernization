package com.terraformers.modernization.analysis;

import com.terraformers.modernization.identity.AuthenticatedUserService;
import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.project.ProjectVisibility;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.storage.StoredUploadObject;
import com.terraformers.modernization.storage.UploadObjectStorageService;
import java.util.UUID;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

@Service
public class AnalysisUploadService {

    private final AuthenticatedUserService authenticatedUserService;
    private final ProjectDomainService projectDomainService;
    private final ProjectArtifactService projectArtifactService;
    private final UploadObjectStorageService uploadObjectStorageService;
    private final AnalysisJobService analysisJobService;

    public AnalysisUploadService(
            AuthenticatedUserService authenticatedUserService,
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            UploadObjectStorageService uploadObjectStorageService,
            AnalysisJobService analysisJobService
    ) {
        this.authenticatedUserService = authenticatedUserService;
        this.projectDomainService = projectDomainService;
        this.projectArtifactService = projectArtifactService;
        this.uploadObjectStorageService = uploadObjectStorageService;
        this.analysisJobService = analysisJobService;
    }

    public AnalysisUploadResponse upload(
            MultipartFile file,
            String requestedProjectName,
            Jwt jwt
    ) {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("file must not be empty");
        }

        UserEntity currentUser = authenticatedUserService.getOrCreate(jwt);
        String originalFilename = safeOriginalFilename(file);
        OwnedProjectEntity project = resolveProject(requestedProjectName, currentUser);

        try {
            StoredUploadObject storedUpload = uploadObjectStorageService.store(
                    file,
                    String.valueOf(project.getProjectId()),
                    originalFilename
            );
            String contentType = resolveContentType(file);

            ProjectFileEntity sourceFile = projectArtifactService.registerSourceImage(
                    project,
                    currentUser,
                    storedUpload,
                    originalFilename,
                    contentType,
                    file.getSize()
            );

            AnalysisJobResponse job = analysisJobService.create(
                    new AnalysisJobRequest(
                            project.getProjectId(),
                            sourceFile.getFileId(),
                            "upload-" + UUID.randomUUID()
                    ),
                    currentUser
            );

            return AnalysisUploadResponse.from(
                    job,
                    originalFilename,
                    contentType,
                    file.getSize(),
                    storedUpload
            );
        } catch (RuntimeException exception) {
            projectDomainService.softDelete(project.getProjectId(), currentUser);
            throw exception;
        }
    }

    private OwnedProjectEntity resolveProject(
            String requestedProjectName,
            UserEntity currentUser
    ) {
        boolean hasProjectName = requestedProjectName != null && !requestedProjectName.isBlank();
        if (!hasProjectName) {
            throw new IllegalArgumentException("projectName must not be blank");
        }
        return projectDomainService.createProject(
                currentUser,
                normalizeProjectName(requestedProjectName),
                null,
                ProjectVisibility.PRIVATE
        );
    }

    private String normalizeProjectName(String requestedProjectName) {
        String candidate = requestedProjectName.strip();
        return candidate.length() <= 200 ? candidate : candidate.substring(0, 200);
    }

    private String safeOriginalFilename(MultipartFile file) {
        String originalFilename = file.getOriginalFilename();
        if (originalFilename == null || originalFilename.isBlank()) {
            return "architecture-image.png";
        }
        String normalized = originalFilename.replace('\\', '/');
        return normalized.substring(normalized.lastIndexOf('/') + 1);
    }

    private String resolveContentType(MultipartFile file) {
        String contentType = file.getContentType();
        return contentType == null || contentType.isBlank() ? "application/octet-stream" : contentType;
    }
}
