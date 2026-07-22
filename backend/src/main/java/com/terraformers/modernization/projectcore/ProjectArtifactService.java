package com.terraformers.modernization.projectcore;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.analysis.AnalysisJobEntity;
import com.terraformers.modernization.analysis.AnalysisJobRepository;
import com.terraformers.modernization.storage.ObjectWriteRequest;
import com.terraformers.modernization.storage.ObjectWriteResult;
import com.terraformers.modernization.storage.ObjectWriter;
import com.terraformers.modernization.storage.StoredUploadObject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectArtifactService {

    public static final String ARCHITECTURE_IMAGE = "ARCHITECTURE_IMAGE";
    public static final String GENERATED_TERRAFORM = "GENERATED_TERRAFORM";
    public static final String TERRAFORM_CONTENT_TYPE = "text/plain; charset=utf-8";

    private final OwnedProjectRepository projectRepository;
    private final ProjectFileRepository fileRepository;
    private final ProjectDomainService projectDomainService;
    private final ObjectWriter objectWriter;
    private final AnalysisJobRepository analysisJobRepository;

    public ProjectArtifactService(
            OwnedProjectRepository projectRepository,
            ProjectFileRepository fileRepository,
            ProjectDomainService projectDomainService,
            ObjectWriter objectWriter,
            AnalysisJobRepository analysisJobRepository
    ) {
        this.projectRepository = projectRepository;
        this.fileRepository = fileRepository;
        this.projectDomainService = projectDomainService;
        this.objectWriter = objectWriter;
        this.analysisJobRepository = analysisJobRepository;
    }

    @Transactional
    public ProjectFileEntity registerSourceImage(
            OwnedProjectEntity project,
            UserEntity uploadedBy,
            StoredUploadObject storedUpload,
            String originalFilename,
            String contentType,
            long sizeBytes
    ) {
        requireActiveProject(project);
        requirePersistedUser(uploadedBy);

        ProjectFileEntity file = new ProjectFileEntity();
        file.setProject(project);
        file.setUploadedBy(uploadedBy);
        file.setNodeType("FILE");
        file.setFileType(ARCHITECTURE_IMAGE);
        file.setPath("source/" + sanitizePathName(originalFilename));
        file.setSortOrder(0);
        file.setOriginalFilename(originalFilename);
        file.setS3Bucket(storedUpload.bucket());
        file.setS3Key(storedUpload.key());
        file.setStorageProvider(storedUpload.provider());
        file.setBinaryPersisted(storedUpload.binaryPersisted());
        file.setStorageETag(storedUpload.eTag());
        file.setContentType(contentType);
        file.setSizeBytes(sizeBytes);
        return fileRepository.save(file);
    }

    @Transactional
    public ProjectFileEntity registerGeneratedTerraform(
            Long projectId,
            String terraformCode,
            ObjectWriteResult writeResult
    ) {
        OwnedProjectEntity project = requireActiveProject(projectId);
        String content = terraformCode == null ? "" : terraformCode;
        Instant deletedAt = Instant.now();

        fileRepository.findByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
                        projectId,
                        GENERATED_TERRAFORM
                )
                .forEach(existing -> existing.setDeletedAt(deletedAt));

        ProjectFileEntity file = new ProjectFileEntity();
        file.setProject(project);
        file.setNodeType("FILE");
        file.setFileType(GENERATED_TERRAFORM);
        file.setPath("terraform/main.tf");
        file.setSortOrder(100);
        file.setOriginalFilename("main.tf");
        file.setS3Bucket(writeResult.bucket());
        file.setS3Key(writeResult.key());
        file.setStorageProvider(writeResult.eTag() == null ? "metadata-only" : "s3");
        file.setBinaryPersisted(writeResult.eTag() != null);
        file.setStorageETag(writeResult.eTag());
        file.setContentType(TERRAFORM_CONTENT_TYPE);
        file.setSizeBytes((long) content.getBytes(StandardCharsets.UTF_8).length);
        file.setChecksum(sha256(content));
        file.setInlineContent(content);
        return fileRepository.save(file);
    }

    @Transactional(readOnly = true)
    public ProjectFileEntity requireLatestSourceImage(Long projectId) {
        return requireLatest(projectId, ARCHITECTURE_IMAGE, "source image");
    }

    @Transactional(readOnly = true)
    public ProjectFileEntity requireLatestTerraform(Long projectId) {
        return requireLatest(projectId, GENERATED_TERRAFORM, "Terraform result");
    }

    @Transactional(readOnly = true)
    public ProjectFileEntity requireLatestJobSourceImage(Long projectId) {
        AnalysisJobEntity job = requireLatestJob(projectId);
        return requireFile(projectId, job.getSourceFileId(), "job source image");
    }

    @Transactional(readOnly = true)
    public ProjectFileEntity requireLatestJobTerraform(Long projectId) {
        AnalysisJobEntity job = requireLatestJob(projectId);
        if (job.getResultFileId() == null) {
            throw new NoSuchElementException("Terraform result is unavailable for latest analysis job: " + projectId);
        }
        return requireFile(projectId, job.getResultFileId(), "job Terraform result");
    }

    private AnalysisJobEntity requireLatestJob(Long projectId) {
        return analysisJobRepository.findFirstByProjectIdOrderByCreatedAtDesc(projectId)
                .orElseThrow(() -> new NoSuchElementException("analysis job not found for project: " + projectId));
    }

    private ProjectFileEntity requireFile(Long projectId, Long fileId, String label) {
        ProjectFileEntity file = fileRepository.findByFileIdAndDeletedAtIsNull(fileId)
                .orElseThrow(() -> new NoSuchElementException(label + " not found for project: " + projectId));
        if (!file.getProject().getProjectId().equals(projectId)) {
            throw new NoSuchElementException(label + " not found for project: " + projectId);
        }
        return file;
    }

    @Transactional
    public ProjectFileEntity updateTerraform(Long projectId, UserEntity currentUser, String content) {
        projectDomainService.requireModifiableProject(projectId, currentUser);
        ProjectFileEntity file = requireLatestTerraform(projectId);
        String normalizedContent = content == null ? "" : content;

        ObjectWriteResult writeResult = objectWriter.writeText(new ObjectWriteRequest(
                file.getS3Bucket(),
                file.getS3Key(),
                normalizedContent,
                TERRAFORM_CONTENT_TYPE
        ));

        file.setInlineContent(normalizedContent);
        file.setSizeBytes((long) normalizedContent.getBytes(StandardCharsets.UTF_8).length);
        file.setChecksum(sha256(normalizedContent));
        file.setS3Bucket(writeResult.bucket());
        file.setS3Key(writeResult.key());
        file.setStorageProvider(writeResult.eTag() == null ? "metadata-only" : "s3");
        file.setBinaryPersisted(writeResult.eTag() != null);
        file.setStorageETag(writeResult.eTag());
        return fileRepository.save(file);
    }

    private ProjectFileEntity requireLatest(Long projectId, String fileType, String label) {
        return fileRepository.findFirstByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
                        projectId,
                        fileType
                )
                .orElseThrow(() -> new NoSuchElementException(label + " not found for project: " + projectId));
    }

    private OwnedProjectEntity requireActiveProject(Long projectId) {
        if (projectId == null) {
            throw new IllegalArgumentException("project id is required");
        }
        return projectRepository.findByProjectIdAndDeletedAtIsNull(projectId)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));
    }

    private void requireActiveProject(OwnedProjectEntity project) {
        if (project == null || project.getProjectId() == null || project.getDeletedAt() != null) {
            throw new IllegalArgumentException("active persisted project is required");
        }
    }

    private void requirePersistedUser(UserEntity user) {
        if (user == null || user.getUserId() == null) {
            throw new IllegalArgumentException("persisted user is required");
        }
    }

    private String sanitizePathName(String value) {
        String sanitized = value == null ? "architecture-image.png" : value.replace('\\', '/');
        sanitized = sanitized.substring(sanitized.lastIndexOf('/') + 1).strip();
        return sanitized.isBlank() ? "architecture-image.png" : sanitized;
    }

    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
