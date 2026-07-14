package com.terraformers.modernization.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.config.RuntimeConfigInspector;
import com.terraformers.modernization.config.RuntimeConfigStatus;
import java.util.List;
import org.junit.jupiter.api.Test;

class RuntimeReadinessControllerTest {

    @Test
    void requiredConfigReturnsRuntimeConfigPresenceOnly() {
        RuntimeConfigInspector inspector = new RuntimeConfigInspector(new TestRuntimeContractProperties()) {
            @Override
            public List<RuntimeConfigStatus> inspectRequiredEnv() {
                return List.of(new RuntimeConfigStatus("SPRING_DATASOURCE_PASSWORD", false));
            }
        };

        RuntimeReadinessController controller = new RuntimeReadinessController(inspector);

        assertThat(controller.requiredConfig())
                .containsExactly(new RuntimeConfigStatus("SPRING_DATASOURCE_PASSWORD", false));
    }

    private static class TestRuntimeContractProperties extends com.terraformers.modernization.config.RuntimeContractProperties {
    }
}
