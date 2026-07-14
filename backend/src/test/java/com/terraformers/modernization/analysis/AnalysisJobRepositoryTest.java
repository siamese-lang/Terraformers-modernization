package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("test")
class AnalysisJobRepositoryTest {

    @Autowired
    private AnalysisJobRepository repository;

    @Test
    void savesAnalysisJobLifecycleState() {
        AnalysisJobEntity entity = new AnalysisJobEntity();
        entity.setProjectId("project-1");
        entity.setSourceBucket("example-bucket");
        entity.setSourceKey("uploads/diagram.png");
        entity.setCorrelationId("corr-1");
        entity.setAnalysisMode(AnalysisMode.INTEGRATED_JAVA);
        entity.setStatus(AnalysisJobStatus.PENDING);

        AnalysisJobEntity saved = repository.saveAndFlush(entity);

        assertThat(saved.getId()).isNotBlank();
        assertThat(saved.getStatus()).isEqualTo(AnalysisJobStatus.PENDING);
        assertThat(saved.getAnalysisMode()).isEqualTo(AnalysisMode.INTEGRATED_JAVA);
        assertThat(saved.getCreatedAt()).isNotNull();
        assertThat(saved.getUpdatedAt()).isNotNull();
    }
}
