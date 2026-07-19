package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class AnalysisRuntimePropertiesTest {

    @Test
    void defaultsBedrockOutputLimitTo8192AndAllowsOverride() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();

        assertThat(properties.getBedrockMaxTokens()).isEqualTo(8192);

        properties.setBedrockMaxTokens(4096);
        assertThat(properties.getBedrockMaxTokens()).isEqualTo(4096);
    }
}
