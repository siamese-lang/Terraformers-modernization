package com.terraformers.modernization.verification;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.analysis.AnalysisJobEntity;
import com.terraformers.modernization.analysis.AnalysisJobRepository;
import com.terraformers.modernization.analysis.AnalysisJobStatus;
import com.terraformers.modernization.analysis.AnalysisMode;
import com.terraformers.modernization.collaboration.BoardEntity;
import com.terraformers.modernization.collaboration.BoardRepository;
import com.terraformers.modernization.collaboration.CommentEntity;
import com.terraformers.modernization.collaboration.CommentRepository;
import com.terraformers.modernization.identity.UserEntity;
import com.terraformers.modernization.identity.UserRepository;
import com.terraformers.modernization.project.ProjectVisibility;
import com.terraformers.modernization.projectcore.OwnedProjectEntity;
import com.terraformers.modernization.projectcore.OwnedProjectRepository;
import com.terraformers.modernization.projectcore.ProjectFileEntity;
import com.terraformers.modernization.projectcore.ProjectFileRepository;
import com.terraformers.modernization.projectcore.ProjectStatus;
import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@ActiveProfiles("prod")
@EnabledIfEnvironmentVariable(named = "SPRING_DATASOURCE_URL", matches = "^jdbc:.*")
@Transactional
class MariaDbRepositorySmokeTest {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private OwnedProjectRepository projectRepository;

    @Autowired
    private ProjectFileRepository projectFileRepository;

    @Autowired
    private AnalysisJobRepository analysisJobRepository;

    @Autowired
    private BoardRepository boardRepository;

    @Autowired
    private CommentRepository commentRepository;

    @Autowired
    private EntityManager entityManager;

    @Test
    void canonicalRepositoryQueriesExecuteAgainstMariaDb() {
        String suffix = UUID.randomUUID().toString();

        UserEntity owner = new UserEntity();
        owner.setCognitoSub("mariadb-smoke-" + suffix);
        owner.setEmail("mariadb-smoke-" + suffix + "@example.com");
        owner.setDisplayName("MariaDB Smoke User");
        owner = userRepository.saveAndFlush(owner);

        OwnedProjectEntity project = new OwnedProjectEntity();
        project.setOwner(owner);
        project.setName("MariaDB Repository Smoke");
        project.setDescription("Exercises canonical repository queries against MariaDB.");
        project.setVisibility(ProjectVisibility.PUBLIC);
        project.setStatus(ProjectStatus.ACTIVE);
        project = projectRepository.saveAndFlush(project);

        ProjectFileEntity sourceFile = new ProjectFileEntity();
        sourceFile.setProject(project);
        sourceFile.setUploadedBy(owner);
        sourceFile.setNodeType("FILE");
        sourceFile.setFileType("ARCHITECTURE_IMAGE");
        sourceFile.setPath("source/architecture.png");
        sourceFile.setOriginalFilename("architecture.png");
        sourceFile.setS3Bucket("validation-bucket");
        sourceFile.setS3Key("repository-smoke/architecture.png");
        sourceFile.setStorageProvider("metadata-only");
        sourceFile.setBinaryPersisted(false);
        sourceFile.setContentType("image/png");
        sourceFile.setSizeBytes(16L);
        sourceFile.setSortOrder(0);
        sourceFile = projectFileRepository.saveAndFlush(sourceFile);

        ProjectFileEntity deletedDraft = new ProjectFileEntity();
        deletedDraft.setProject(project);
        deletedDraft.setUploadedBy(owner);
        deletedDraft.setNodeType("FILE");
        deletedDraft.setFileType("GENERATED_TERRAFORM");
        deletedDraft.setPath("terraform/main-old.tf");
        deletedDraft.setInlineContent("terraform {}");
        deletedDraft.setContentType("text/plain; charset=utf-8");
        deletedDraft.setSizeBytes(12L);
        deletedDraft.setChecksum("deleted-checksum");
        deletedDraft.setSortOrder(1);
        deletedDraft.setDeletedAt(Instant.now());
        projectFileRepository.saveAndFlush(deletedDraft);

        ProjectFileEntity resultFile = new ProjectFileEntity();
        resultFile.setProject(project);
        resultFile.setUploadedBy(owner);
        resultFile.setNodeType("FILE");
        resultFile.setFileType("GENERATED_TERRAFORM");
        resultFile.setPath("terraform/main.tf");
        resultFile.setS3Bucket("validation-bucket");
        resultFile.setS3Key("repository-smoke/main.tf");
        resultFile.setStorageProvider("metadata-only");
        resultFile.setBinaryPersisted(false);
        resultFile.setContentType("text/plain; charset=utf-8");
        resultFile.setInlineContent("terraform { required_version = \">= 1.6.0\" }");
        resultFile.setSizeBytes(41L);
        resultFile.setChecksum("active-checksum");
        resultFile.setSortOrder(2);
        resultFile = projectFileRepository.saveAndFlush(resultFile);

        AnalysisJobEntity job = new AnalysisJobEntity();
        job.setProjectId(project.getProjectId());
        job.setSourceFileId(sourceFile.getFileId());
        job.setResultFileId(resultFile.getFileId());
        job.setSourceBucket(sourceFile.getS3Bucket());
        job.setSourceKey(sourceFile.getS3Key());
        job.setCorrelationId("repository-smoke");
        job.setStatus(AnalysisJobStatus.SUCCEEDED);
        job.setAnalysisMode(AnalysisMode.INTEGRATED_JAVA);
        job.setProvider("repository-smoke-provider");
        job.setResultObjectKey(resultFile.getS3Key());
        job.setResultPreview("terraform {}");
        job = analysisJobRepository.saveAndFlush(job);

        BoardEntity board = new BoardEntity();
        board.setProject(project);
        board.setAuthor(owner);
        board.setTitle(BoardEntity.PUBLIC_DISCUSSION_TITLE);
        board.setContent("Public project discussion");
        board.setCategory(BoardEntity.PUBLIC_DISCUSSION_CATEGORY);
        board = boardRepository.saveAndFlush(board);

        CommentEntity comment = new CommentEntity();
        comment.setBoard(board);
        comment.setAuthor(owner);
        comment.setContent("Repository smoke comment");
        comment = commentRepository.saveAndFlush(comment);

        Long ownerId = owner.getUserId();
        Long projectId = project.getProjectId();
        Long sourceFileId = sourceFile.getFileId();
        Long resultFileId = resultFile.getFileId();
        String jobId = job.getId();
        Long boardId = board.getBoardId();
        Long commentId = comment.getCommentId();

        entityManager.flush();
        entityManager.clear();

        assertThat(userRepository.findByCognitoSub("mariadb-smoke-" + suffix))
                .get()
                .extracting(UserEntity::getUserId)
                .isEqualTo(ownerId);
        assertThat(projectRepository.findByOwner_UserIdAndDeletedAtIsNullOrderByCreatedAtDesc(ownerId))
                .extracting(OwnedProjectEntity::getProjectId)
                .containsExactly(projectId);
        assertThat(projectRepository.findByVisibilityAndDeletedAtIsNullOrderByCreatedAtDesc(ProjectVisibility.PUBLIC))
                .extracting(OwnedProjectEntity::getProjectId)
                .contains(projectId);
        assertThat(projectRepository.existsByProjectIdAndOwner_UserIdAndDeletedAtIsNull(projectId, ownerId)).isTrue();

        List<ProjectFileEntity> activeFiles = projectFileRepository
                .findByProject_ProjectIdAndDeletedAtIsNullOrderBySortOrderAscCreatedAtAsc(projectId);
        assertThat(activeFiles)
                .extracting(ProjectFileEntity::getPath)
                .containsExactly("source/architecture.png", "terraform/main.tf");
        assertThat(activeFiles)
                .extracting(ProjectFileEntity::getFileId)
                .containsExactly(sourceFileId, resultFileId);

        assertThat(analysisJobRepository.findFirstByProjectIdOrderByCreatedAtDesc(projectId))
                .get()
                .satisfies(found -> {
                    assertThat(found.getId()).isEqualTo(jobId);
                    assertThat(found.getSourceFileId()).isEqualTo(sourceFileId);
                    assertThat(found.getResultFileId()).isEqualTo(resultFileId);
                });
        assertThat(boardRepository.findFirstByProject_ProjectIdAndCategoryAndDeletedAtIsNullOrderByCreatedAtAsc(
                projectId,
                BoardEntity.PUBLIC_DISCUSSION_CATEGORY
        )).get().extracting(BoardEntity::getBoardId).isEqualTo(boardId);
        assertThat(commentRepository.findByBoard_BoardIdAndDeletedAtIsNullOrderByCreatedAtAsc(boardId))
                .extracting(CommentEntity::getCommentId)
                .containsExactly(commentId);
    }
}
