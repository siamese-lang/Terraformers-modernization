package com.terraformers.modernization.collaboration;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CommentRepository extends JpaRepository<CommentEntity, Long> {

    List<CommentEntity> findByBoard_BoardIdAndDeletedAtIsNullOrderByCreatedAtAsc(Long boardId);
}
