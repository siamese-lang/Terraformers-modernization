package com.terraformers.modernization.projectcomment;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectCommentRepository extends JpaRepository<ProjectCommentEntity, Long> {

    List<ProjectCommentEntity> findAllByProjectIdOrderByCreatedAtAsc(String projectId);
}
