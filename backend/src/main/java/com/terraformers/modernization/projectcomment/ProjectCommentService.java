package com.terraformers.modernization.projectcomment;

import com.terraformers.modernization.collaboration.BoardEntity;
import com.terraformers.modernization.collaboration.BoardRepository;
import com.terraformers.modernization.collaboration.CollaborationStatus;
import com.terraformers.modernization.collaboration.CommentEntity;
import com.terraformers.modernization.collaboration.CommentRepository;
import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.project.ProjectVisibility;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.ProjectDomainService;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class ProjectCommentService {

    private final ProjectDomainService projectDomainService;
    private final BoardRepository boardRepository;
    private final CommentRepository commentRepository;

    public ProjectCommentService(
            ProjectDomainService projectDomainService,
            BoardRepository boardRepository,
            CommentRepository commentRepository
    ) {
        this.projectDomainService = projectDomainService;
        this.boardRepository = boardRepository;
        this.commentRepository = commentRepository;
    }

    @Transactional(readOnly = true)
    public List<ProjectCommentResponse> listPublicProjectComments(Long projectId) {
        ensurePublicProject(projectId);
        return boardRepository
                .findFirstByProject_ProjectIdAndCategoryAndDeletedAtIsNullOrderByCreatedAtAsc(
                        projectId,
                        BoardEntity.PUBLIC_DISCUSSION_CATEGORY
                )
                .map(board -> commentRepository
                        .findByBoard_BoardIdAndDeletedAtIsNullOrderByCreatedAtAsc(board.getBoardId())
                        .stream()
                        .map(ProjectCommentResponse::from)
                        .toList())
                .orElseGet(List::of);
    }

    @Transactional
    public ProjectCommentResponse createPublicProjectComment(
            Long projectId,
            ProjectCommentCreateRequest request,
            UserEntity currentUser
    ) {
        if (currentUser == null || currentUser.getUserId() == null) {
            throw new IllegalArgumentException("persisted authenticated user is required");
        }

        OwnedProjectEntity project = ensurePublicProject(projectId);
        BoardEntity board = boardRepository
                .findFirstByProject_ProjectIdAndCategoryAndDeletedAtIsNullOrderByCreatedAtAsc(
                        projectId,
                        BoardEntity.PUBLIC_DISCUSSION_CATEGORY
                )
                .orElseGet(() -> createDiscussionBoard(project, currentUser));

        CommentEntity entity = new CommentEntity();
        entity.setBoard(board);
        entity.setAuthor(currentUser);
        entity.setContent(request.content().strip());
        entity.setStatus(CollaborationStatus.ACTIVE);
        return ProjectCommentResponse.from(commentRepository.save(entity));
    }

    private BoardEntity createDiscussionBoard(OwnedProjectEntity project, UserEntity currentUser) {
        BoardEntity board = new BoardEntity();
        board.setProject(project);
        board.setAuthor(currentUser);
        board.setTitle(BoardEntity.PUBLIC_DISCUSSION_TITLE);
        board.setContent("Public discussion for project " + project.getProjectId());
        board.setCategory(BoardEntity.PUBLIC_DISCUSSION_CATEGORY);
        board.setStatus(CollaborationStatus.ACTIVE);
        return boardRepository.save(board);
    }

    private OwnedProjectEntity ensurePublicProject(Long projectId) {
        OwnedProjectEntity project = projectDomainService.requireAccessibleProject(projectId, null);
        if (project.getVisibility() != ProjectVisibility.PUBLIC) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "project is not public: " + projectId);
        }
        return project;
    }
}
