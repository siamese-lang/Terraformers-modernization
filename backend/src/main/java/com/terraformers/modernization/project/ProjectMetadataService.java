package com.terraformers.modernization.project;

import com.terraformers.modernization.analysis.AnalysisJobEntity;
import com.terraformers.modernization.analysis.AnalysisJobRepository;
import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectArtifactService;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectMetadataService {

    private final ProjectDomainService projectDomainService;
    private final ProjectArtifactService projectArtifactService;
    private final ProjectFileRepository fileRepository;
    private final AnalysisJobRepository analysisJobRepository;

    public ProjectMetadataService(
            ProjectDomainService projectDomainService,
            ProjectArtifactService projectArtifactService,
            ProjectFileRepository fileRepository,
            AnalysisJobRepository analysisJobRepository
    ) {
        this.projectDomainService = projectDomainService;
        this.projectArtifactService = projectArtifactService;
        this.fileRepository = fileRepository;
        this.analysisJobRepository = analysisJobRepository;
    }

    @Transactional(readOnly = true)
    public ProjectResponse get(Long projectId, UserEntity currentUser) {
        return toResponse(projectDomainService.requireAccessibleProject(projectId, currentUser));
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> list(UserEntity currentUser) {
        return projectDomainService.findOwnedProjects(currentUser).stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<ProjectResponse> listPublic() {
        return projectDomainService.findPublicProjects().stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional
    public void delete(Long projectId, UserEntity currentUser) {
        projectDomainService.softDelete(projectId, currentUser);
    }

    public ProjectResponse updateVisibility(
            Long projectId,
            UserEntity currentUser,
            ProjectVisibility visibility
    ) {
        return toResponse(projectDomainService.updateVisibility(projectId, currentUser, visibility));
    }

    @Transactional(readOnly = true)
    public TerraformDraftResponse getTerraformDraft(Long projectId, UserEntity currentUser) {
        OwnedProjectEntity project = projectDomainService.requireAccessibleProject(projectId, currentUser);
        ProjectFileEntity terraformFile = projectArtifactService.requireLatestTerraform(projectId);
        AnalysisJobEntity latestJob = analysisJobRepository.findFirstByProjectIdOrderByCreatedAtDesc(projectId)
                .orElse(null);
        return TerraformDraftResponse.from(project, terraformFile, latestJob);
    }

    @Transactional
    public TerraformDraftResponse updateTerraformDraft(
            Long projectId,
            UserEntity currentUser,
            String content
    ) {
        OwnedProjectEntity project = projectDomainService.requireModifiableProject(projectId, currentUser);
        ProjectFileEntity terraformFile = projectArtifactService.updateTerraform(projectId, currentUser, content);
        AnalysisJobEntity latestJob = analysisJobRepository.findFirstByProjectIdOrderByCreatedAtDesc(projectId)
                .orElse(null);
        return TerraformDraftResponse.from(project, terraformFile, latestJob);
    }

    private ProjectResponse toResponse(OwnedProjectEntity project) {
        Long projectId = project.getProjectId();
        ProjectFileEntity sourceFile = fileRepository
                .findFirstByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
                        projectId,
                        ProjectArtifactService.ARCHITECTURE_IMAGE
                )
                .orElse(null);
        ProjectFileEntity terraformFile = fileRepository
                .findFirstByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
                        projectId,
                        ProjectArtifactService.GENERATED_TERRAFORM
                )
                .orElse(null);
        AnalysisJobEntity latestJob = analysisJobRepository.findFirstByProjectIdOrderByCreatedAtDesc(projectId)
                .orElse(null);
        return ProjectResponse.from(project, sourceFile, terraformFile, latestJob);
    }
}
