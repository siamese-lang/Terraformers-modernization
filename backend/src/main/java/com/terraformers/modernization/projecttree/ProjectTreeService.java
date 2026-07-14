package com.terraformers.modernization.projecttree;

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
    public List<ProjectTreeNode> listTrees() {
        return projectMetadataService.list().stream()
                .map(this::toRootNode)
                .toList();
    }

    @Transactional(readOnly = true)
    public ProjectTreeResponse getTree(String projectId) {
        ProjectResponse project = projectMetadataService.get(projectId);
        return new ProjectTreeResponse(
                project.projectId(),
                project.displayName(),
                project.visibility().name(),
                project.latestAnalysisJobId(),
                project.latestResultObjectKey(),
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
        if (project.sourceBucket() == null || project.sourceKey() == null) {
            return null;
        }

        String folderId = project.projectId() + ":source";
        ProjectTreeNode sourceFile = ProjectTreeNode.file(
                project.projectId() + ":source:" + safeNodeId(project.sourceKey()),
                displaySourceName(project),
                project.projectId(),
                folderId,
                "/api/projects/" + project.projectId() + "/source",
                project.sourceBucket(),
                project.sourceKey(),
                null
        );

        return ProjectTreeNode.folder(folderId, "source", project.projectId(), project.projectId(), List.of(sourceFile));
    }

    private ProjectTreeNode buildTerraformFolder(ProjectResponse project) {
        if (project.latestResultObjectKey() == null || project.latestResultObjectKey().isBlank()) {
            return null;
        }

        String folderId = project.projectId() + ":terraform";
        ProjectTreeNode mainTf = ProjectTreeNode.file(
                project.projectId() + ":terraform:main.tf",
                "main.tf",
                project.projectId(),
                folderId,
                "/api/projects/" + project.projectId() + "/terraform/main.tf",
                null,
                null,
                project.latestResultObjectKey()
        );

        return ProjectTreeNode.folder(folderId, "terraform", project.projectId(), project.projectId(), List.of(mainTf));
    }

    private String displaySourceName(ProjectResponse project) {
        if (project.originalFilename() != null && !project.originalFilename().isBlank()) {
            return project.originalFilename();
        }
        int slash = project.sourceKey().lastIndexOf('/');
        return slash >= 0 ? project.sourceKey().substring(slash + 1) : project.sourceKey();
    }

    private String safeNodeId(String value) {
        return value.replaceAll("[^a-zA-Z0-9._:-]+", "-");
    }
}
