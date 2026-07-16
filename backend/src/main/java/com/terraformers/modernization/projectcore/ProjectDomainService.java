package com.terraformers.modernization.projectcore;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.identity.UserRole;
import com.terraformers.modernization.project.ProjectVisibility;
import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectDomainService {

    private final OwnedProjectRepository projectRepository;
    private final ProjectFileRepository fileRepository;

    public ProjectDomainService(
            OwnedProjectRepository projectRepository,
            ProjectFileRepository fileRepository
    ) {
        this.projectRepository = projectRepository;
        this.fileRepository = fileRepository;
    }

    @Transactional
    public OwnedProjectEntity createProject(
            UserEntity owner,
            String name,
            String description,
            ProjectVisibility visibility
    ) {
        requirePersistedUser(owner);
        String normalizedName = requireName(name);

        OwnedProjectEntity project = new OwnedProjectEntity();
        project.setOwner(owner);
        project.setName(normalizedName);
        project.setDescription(description);
        project.setVisibility(visibility == null ? ProjectVisibility.PRIVATE : visibility);
        project.setStatus(ProjectStatus.ACTIVE);
        return projectRepository.save(project);
    }

    @Transactional(readOnly = true)
    public List<OwnedProjectEntity> findOwnedProjects(UserEntity owner) {
        requirePersistedUser(owner);
        return projectRepository.findByOwner_UserIdAndDeletedAtIsNullOrderByCreatedAtDesc(owner.getUserId());
    }

    @Transactional(readOnly = true)
    public List<OwnedProjectEntity> findPublicProjects() {
        return projectRepository.findByVisibilityAndDeletedAtIsNullOrderByCreatedAtDesc(ProjectVisibility.PUBLIC);
    }

    @Transactional(readOnly = true)
    public OwnedProjectEntity requireAccessibleProject(Long projectId, UserEntity currentUser) {
        OwnedProjectEntity project = requireActiveProject(projectId);
        if (!isAccessible(project, currentUser)) {
            throw new SecurityException("project access denied: " + projectId);
        }
        return project;
    }

    @Transactional(readOnly = true)
    public OwnedProjectEntity requireModifiableProject(Long projectId, UserEntity currentUser) {
        requirePersistedUser(currentUser);
        OwnedProjectEntity project = requireActiveProject(projectId);
        requireOwnerOrAdmin(project, currentUser);
        return project;
    }

    @Transactional
    public OwnedProjectEntity updateVisibility(
            Long projectId,
            UserEntity currentUser,
            ProjectVisibility visibility
    ) {
        OwnedProjectEntity project = requireModifiableProject(projectId, currentUser);
        project.setVisibility(visibility == null ? ProjectVisibility.PRIVATE : visibility);
        return projectRepository.save(project);
    }

    @Transactional
    public void softDelete(Long projectId, UserEntity currentUser) {
        OwnedProjectEntity project = requireModifiableProject(projectId, currentUser);
        project.setStatus(ProjectStatus.DELETED);
        project.setDeletedAt(Instant.now());
        projectRepository.save(project);
    }

    @Transactional
    public ProjectFileEntity registerFile(
            OwnedProjectEntity project,
            UserEntity uploadedBy,
            ProjectFileEntity parentFile,
            String nodeType,
            String fileType,
            String path,
            String originalFilename,
            String s3Bucket,
            String s3Key,
            String contentType,
            Long sizeBytes,
            String checksum,
            Integer sortOrder
    ) {
        if (project == null || project.getProjectId() == null || project.getDeletedAt() != null) {
            throw new IllegalArgumentException("active persisted project is required");
        }
        requirePersistedUser(uploadedBy);
        if (path == null || path.isBlank()) {
            throw new IllegalArgumentException("file path is required");
        }
        if (nodeType == null || nodeType.isBlank()) {
            throw new IllegalArgumentException("node type is required");
        }
        if (parentFile != null
                && (parentFile.getProject() == null
                || !project.getProjectId().equals(parentFile.getProject().getProjectId()))) {
            throw new IllegalArgumentException("parent file must belong to the same project");
        }

        ProjectFileEntity file = new ProjectFileEntity();
        file.setProject(project);
        file.setUploadedBy(uploadedBy);
        file.setParentFile(parentFile);
        file.setNodeType(nodeType.trim().toUpperCase());
        file.setFileType(fileType);
        file.setPath(path.trim());
        file.setOriginalFilename(originalFilename);
        file.setS3Bucket(s3Bucket);
        file.setS3Key(s3Key);
        file.setContentType(contentType);
        file.setSizeBytes(sizeBytes);
        file.setChecksum(checksum);
        file.setSortOrder(sortOrder == null ? 0 : sortOrder);
        return fileRepository.save(file);
    }

    private OwnedProjectEntity requireActiveProject(Long projectId) {
        if (projectId == null) {
            throw new IllegalArgumentException("project id is required");
        }
        return projectRepository.findByProjectIdAndDeletedAtIsNull(projectId)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));
    }

    private boolean isAccessible(OwnedProjectEntity project, UserEntity currentUser) {
        if (project.getVisibility() == ProjectVisibility.PUBLIC) {
            return true;
        }
        return currentUser != null
                && (isOwner(project, currentUser) || currentUser.getRole() == UserRole.ADMIN);
    }

    private void requireOwnerOrAdmin(OwnedProjectEntity project, UserEntity currentUser) {
        if (!isOwner(project, currentUser) && currentUser.getRole() != UserRole.ADMIN) {
            throw new SecurityException("project modification denied: " + project.getProjectId());
        }
    }

    private boolean isOwner(OwnedProjectEntity project, UserEntity currentUser) {
        return currentUser != null
                && currentUser.getUserId() != null
                && project.getOwner() != null
                && project.getOwner().getUserId() != null
                && project.getOwner().getUserId().equals(currentUser.getUserId());
    }

    private void requirePersistedUser(UserEntity user) {
        if (user == null || user.getUserId() == null) {
            throw new IllegalArgumentException("persisted user is required");
        }
    }

    private String requireName(String name) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("project name is required");
        }
        return name.trim();
    }
}
