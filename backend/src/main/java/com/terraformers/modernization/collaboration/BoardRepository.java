package com.terraformers.modernization.collaboration;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BoardRepository extends JpaRepository<BoardEntity, Long> {

    Optional<BoardEntity> findFirstByProject_ProjectIdAndCategoryAndDeletedAtIsNullOrderByCreatedAtAsc(
            Long projectId,
            String category
    );
}
