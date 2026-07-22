package com.terraformers.modernization.analysis;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AnalysisJobRepository extends JpaRepository<AnalysisJobEntity, String> {

    Optional<AnalysisJobEntity> findFirstByProjectIdOrderByCreatedAtDesc(Long projectId);
}
