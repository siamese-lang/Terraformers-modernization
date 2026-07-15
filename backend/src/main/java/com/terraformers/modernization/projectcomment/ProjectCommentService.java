package com.terraformers.modernization.projectcomment;

import com.terraformers.modernization.project.ProjectEntity;
import com.terraformers.modernization.project.ProjectRepository;
import com.terraformers.modernization.project.ProjectVisibility;
import java.util.List;
import java.util.NoSuchElementException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ProjectCommentService {

    private final ProjectRepository projectRepository;
    private final ProjectCommentRepository commentRepository;

    public ProjectCommentService(
            ProjectRepository projectRepository,
            ProjectCommentRepository commentRepository
    ) {
        this.projectRepository = projectRepository;
        this.commentRepository = commentRepository;
    }

    @Transactional(readOnly = true)
    public List<ProjectCommentResponse> listPublicProjectComments(String projectId) {
        ensurePublicProject(projectId);
        return commentRepository.findAllByProjectIdOrderByCreatedAtAsc(projectId).stream()
                .map(ProjectCommentResponse::from)
                .toList();
    }

    @Transactional
    public ProjectCommentResponse createPublicProjectComment(String projectId, ProjectCommentCreateRequest request) {
        ensurePublicProject(projectId);

        ProjectCommentEntity entity = new ProjectCommentEntity();
        entity.setProjectId(projectId);
        entity.setContent(request.content().strip());
        entity.setUserEmail(normalizeUserEmail(request.userEmail()));

        return ProjectCommentResponse.from(commentRepository.save(entity));
    }

    private ProjectEntity ensurePublicProject(String projectId) {
        ProjectEntity project = projectRepository.findById(projectId)
                .orElseThrow(() -> new NoSuchElementException("project not found: " + projectId));

        if (project.getVisibility() != ProjectVisibility.PUBLIC) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "project is not public: " + projectId);
        }

        return project;
    }

    private String normalizeUserEmail(String userEmail) {
        if (userEmail == null || userEmail.isBlank()) {
            return "anonymous";
        }
        return userEmail.strip();
    }
}
