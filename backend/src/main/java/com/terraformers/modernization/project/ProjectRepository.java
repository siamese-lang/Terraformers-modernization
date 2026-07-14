package com.terraformers.modernization.project;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<ProjectEntity, String> {

    List<ProjectEntity> findAllByVisibilityOrderByUpdatedAtDesc(ProjectVisibility visibility);
}
