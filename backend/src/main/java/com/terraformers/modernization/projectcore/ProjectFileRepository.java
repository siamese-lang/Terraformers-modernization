package com.terraformers.modernization.projectcore;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectFileRepository extends JpaRepository<ProjectFileEntity, Long> {

    List<ProjectFileEntity> findByProject_ProjectIdAndDeletedAtIsNullOrderBySortOrderAscCreatedAtAsc(Long projectId);

    Optional<ProjectFileEntity> findByFileIdAndDeletedAtIsNull(Long fileId);

    Optional<ProjectFileEntity> findFirstByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
            Long projectId,
            String fileType
    );

    List<ProjectFileEntity> findByProject_ProjectIdAndFileTypeAndDeletedAtIsNullOrderByCreatedAtDesc(
            Long projectId,
            String fileType
    );
}
