package com.terraformers.modernization.analysis.bedrock;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;

class BedrockRuntimeConfigurationTest {

    private String originalRegion;

    @BeforeEach
    void setRegionForClientCreation() {
        originalRegion = System.getProperty("aws.region");
        System.setProperty("aws.region", "ap-northeast-2");
    }

    @AfterEach
    void restoreRegion() {
        if (originalRegion == null) {
            System.clearProperty("aws.region");
        } else {
            System.setProperty("aws.region", originalRegion);
        }
    }

    @Test
    void createsBedrockClientWithExplicitTimeoutHierarchy() {
        BedrockRuntimeConfiguration configuration = new BedrockRuntimeConfiguration();

        BedrockRuntimeClient client = configuration.bedrockRuntimeClient();

        assertThat(client).isNotNull();
        assertThat(BedrockRuntimeConfiguration.CONNECTION_TIMEOUT).isEqualTo(java.time.Duration.ofSeconds(5));
        assertThat(BedrockRuntimeConfiguration.SOCKET_TIMEOUT).isEqualTo(java.time.Duration.ofSeconds(150));
        assertThat(BedrockRuntimeConfiguration.API_CALL_ATTEMPT_TIMEOUT).isEqualTo(java.time.Duration.ofSeconds(165));
        assertThat(BedrockRuntimeConfiguration.API_CALL_TIMEOUT).isEqualTo(java.time.Duration.ofSeconds(180));
        assertThat(BedrockRuntimeConfiguration.SOCKET_TIMEOUT)
                .isLessThan(BedrockRuntimeConfiguration.API_CALL_ATTEMPT_TIMEOUT);
        assertThat(BedrockRuntimeConfiguration.API_CALL_ATTEMPT_TIMEOUT)
                .isLessThan(BedrockRuntimeConfiguration.API_CALL_TIMEOUT);
        client.close();
    }
}
