package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import com.terraformers.modernization.reference.RetrievalMode;

import org.junit.jupiter.api.Test;

class AnalysisRuntimePropertiesTest {

    @Test
    void defaultsBedrockOutputLimitTo8192AndAllowsOverride() {
        AnalysisRuntimeProperties properties = new AnalysisRuntimeProperties();

        assertThat(properties.getBedrockMaxTokens()).isEqualTo(8192);

        properties.setBedrockMaxTokens(4096);
        assertThat(properties.getBedrockMaxTokens()).isEqualTo(4096);
    }

    @Test
    void defaultsRetrievalToDisabled() {
        assertThat(new AnalysisRuntimeProperties().getRetrievalMode()).isEqualTo(RetrievalMode.DISABLED);
    }
}
