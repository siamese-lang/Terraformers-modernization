package com.terraformers.modernization.analysis;

import org.springframework.data.jpa.repository.JpaRepository;

public interface AnalysisJobRepository extends JpaRepository<AnalysisJobEntity, String> {
}
