package com.terraformers.modernization.projecttree;

import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.project.ProjectMetadataService;
import com.terraformers.modernization.project.ProjectResponse;
import com.terraformers.modernization.project.ProjectVisibility;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectTreeService {

    private final ProjectMetadataService projectMetadataService;

    public ProjectTreeService(ProjectMetadataService projectMetadataService) {
        this.projectMetadataService = projectMetadataService;
    }

    @Transactional(readOnly = true)
    public List<ProjectTreeNode> listTrees(UserEntity currentUser) {
        return projectMetadataService.list(currentUser).stream()
                .map(this::toRootNode)
                .toList();
    }

    @Transactional(readOnly = true)
    public ProjectTreeResponse getTree(Long projectId, UserEntity currentUser) {
        ProjectResponse project = projectMetadataService.get(projectId, currentUser);
        return new ProjectTreeResponse(
                project.projectId(),
                project.displayName(),
                project.visibility().name(),
                project.latestAnalysisJobId(),
                project.latestResultFileId(),
                project.latestResultObjectKey(),
                project.analysisStatus(),
                project.analysisSummary(),
                project.detectedComponents(),
                project.detectedRelationships(),
                project.warnings(),
                project.updatedAt(),
                List.of(toRootNode(project))
        );
    }

    private ProjectTreeNode toRootNode(ProjectResponse project) {
        List<ProjectTreeNode> children = new ArrayList<>();

        ProjectTreeNode sourceFolder = buildSourceFolder(project);
        if (sourceFolder != null) {
            children.add(sourceFolder);
        }

        ProjectTreeNode terraformFolder = buildTerraformFolder(project);
        if (terraformFolder != null) {
            children.add(terraformFolder);
        }

        return ProjectTreeNode.project(
                project.projectId(),
                project.displayName(),
                project.visibility() == ProjectVisibility.PRIVATE,
                children
        );
    }

    private ProjectTreeNode buildSourceFolder(ProjectResponse project) {
        if (project.sourceFileId() == null || project.sourceBucket() == null || project.sourceKey() == null) {
            return null;
        }

        String projectId = String.valueOf(project.projectId());
        String folderId = projectId + ":source";
        ProjectTreeNode sourceFile = ProjectTreeNode.file(
                projectId + ":source:" + project.sourceFileId(),
                displaySourceName(project),
                project.projectId(),
                folderId,
                "/api/projects/" + projectId + "/source-object",
                project.sourceBucket(),
                project.sourceKey(),
                null
        );

        return ProjectTreeNode.folder(
                folderId,
                "source",
                project.projectId(),
                projectId,
                List.of(sourceFile)
        );
    }

    private ProjectTreeNode buildTerraformFolder(ProjectResponse project) {
        if (project.latestResultFileId() == null) {
            return null;
        }

        String projectId = String.valueOf(project.projectId());
        String folderId = projectId + ":terraform";
        ProjectTreeNode mainTf = ProjectTreeNode.file(
                projectId + ":terraform:" + project.latestResultFileId(),
                "main.tf",
                project.projectId(),
                folderId,
                "/api/projects/" + projectId + "/terraform/main.tf",
                null,
                null,
                project.latestResultObjectKey()
        );

        return ProjectTreeNode.folder(
                folderId,
                "terraform",
                project.projectId(),
                projectId,
                List.of(mainTf)
        );
    }

    private String displaySourceName(ProjectResponse project) {
        if (project.originalFilename() != null && !project.originalFilename().isBlank()) {
            return project.originalFilename();
        }
        int slash = project.sourceKey().lastIndexOf('/');
        return slash >= 0 ? project.sourceKey().substring(slash + 1) : project.sourceKey();
    }
}
