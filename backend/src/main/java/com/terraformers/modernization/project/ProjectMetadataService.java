package com.terraformers.modernization.project;

import com.terraformers.modernization.analysis.AnalysisUploadResponse;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectMetadataService {

    private final ProjectRepository repository;

    public ProjectMetadataService(ProjectRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public ProjectResponse upsertFromUpload(AnalysisUploadResponse upload) {
        ProjectEntity entity = repository.findById(upload.projectId())
                .orElseGet(() -> newProject(upload.projectId(), upload.originalFilename()));

        entity.setLatestAnalysisJobId(upload.analysisJobId());
        entity.setLatestResultObjectKey(upload.resultObjectKey());
        entity.setSourceBucket(upload.sourceBucket());
        entity.setSourceKey(upload.sourceKey());
        entity.setOriginalFilename(upload.originalFilename());
        entity.setContentType(upload.contentType());
        entity.setUploadSizeBytes(upload.size());

        return ProjectResponse.from(repository.save(entity));
    }

    @Transactional(readOnly = true)
    public ProjectResponse get(String projectId) {
        return repository.findById(projectId)
                .map(ProjectResponse::from)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> list() {
        return repository.findAll().stream()
                .map(ProjectResponse::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> listPublic() {
        return repository.findAllByVisibilityOrderByUpdatedAtDesc(ProjectVisibility.PUBLIC).stream()
                .map(ProjectResponse::from)
                .toList();
    }

    @Transactional
    public ProjectResponse updateVisibility(String projectId, ProjectVisibility visibility) {
        ProjectEntity entity = repository.findById(projectId)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));
        entity.setVisibility(visibility);
        return ProjectResponse.from(repository.save(entity));
    }

    private ProjectEntity newProject(String projectId, String originalFilename) {
        ProjectEntity entity = new ProjectEntity();
        entity.setProjectId(projectId);
        entity.setDisplayName(displayNameFrom(projectId, originalFilename));
        entity.setVisibility(ProjectVisibility.PRIVATE);
        return entity;
    }

    private String displayNameFrom(String projectId, String originalFilename) {
        if (originalFilename == null || originalFilename.isBlank()) {
            return projectId;
        }

        String displayName = originalFilename;
        int dotIndex = displayName.lastIndexOf('.');
        if (dotIndex > 0) {
            displayName = displayName.substring(0, dotIndex);
        }

        displayName = displayName.strip();
        return displayName.isBlank() ? projectId : displayName;
    }
}
