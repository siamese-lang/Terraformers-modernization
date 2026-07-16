package com.terraformers.modernization.projectcore;

import com.terraformers.modernization.project.ProjectVisibility;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OwnedProjectRepository extends JpaRepository<OwnedProjectEntity, Long> {

    List<OwnedProjectEntity> findByOwner_UserIdAndDeletedAtIsNullOrderByCreatedAtDesc(Long ownerUserId);

    Optional<OwnedProjectEntity> findByProjectIdAndDeletedAtIsNull(Long projectId);

    List<OwnedProjectEntity> findByVisibilityAndDeletedAtIsNullOrderByCreatedAtDesc(ProjectVisibility visibility);

    boolean existsByProjectIdAndOwner_UserIdAndDeletedAtIsNull(Long projectId, Long ownerUserId);
}
