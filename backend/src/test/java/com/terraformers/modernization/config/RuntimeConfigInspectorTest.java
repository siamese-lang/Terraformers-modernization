package com.terraformers.modernization.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class RuntimeConfigInspectorTest {

    @Test
    void inspectRequiredEnvMarksPresentAndMissingKeysWithoutExposingValues() {
        RuntimeContractProperties properties = new RuntimeContractProperties();
        properties.setRequiredEnv(List.of("SPRING_DATASOURCE_URL", "SPRING_DATASOURCE_PASSWORD", "S3_BUCKET_NAME"));

        Map<String, String> env = Map.of(
                "SPRING_DATASOURCE_URL", "jdbc:mariadb://example:3306/app",
                "S3_BUCKET_NAME", "example-bucket"
        );

        RuntimeConfigInspector inspector = new RuntimeConfigInspector(properties, env::get);

        List<RuntimeConfigStatus> result = inspector.inspectRequiredEnv();

        assertThat(result)
                .containsExactly(
                        new RuntimeConfigStatus("SPRING_DATASOURCE_URL", true),
                        new RuntimeConfigStatus("SPRING_DATASOURCE_PASSWORD", false),
                        new RuntimeConfigStatus("S3_BUCKET_NAME", true)
                );
    }

    @Test
    void blankValuesAreTreatedAsMissing() {
        RuntimeContractProperties properties = new RuntimeContractProperties();
        properties.setRequiredEnv(List.of("AI_LOG_QUEUE_URL"));

        RuntimeConfigInspector inspector = new RuntimeConfigInspector(properties, key -> "   ");

        assertThat(inspector.inspectRequiredEnv())
                .containsExactly(new RuntimeConfigStatus("AI_LOG_QUEUE_URL", false));
    }
}
