package com.terraformers.modernization.analysis.bedrock;

import java.time.Duration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;

@Configuration
public class BedrockRuntimeConfiguration {

    static final Duration CONNECTION_TIMEOUT = Duration.ofSeconds(5);
    static final Duration SOCKET_TIMEOUT = Duration.ofSeconds(150);
    static final Duration API_CALL_ATTEMPT_TIMEOUT = Duration.ofSeconds(165);
    static final Duration API_CALL_TIMEOUT = Duration.ofSeconds(180);

    @Bean
    @Lazy
    BedrockRuntimeClient bedrockRuntimeClient() {
        return BedrockRuntimeClient.builder()
                .httpClientBuilder(ApacheHttpClient.builder()
                        .connectionTimeout(CONNECTION_TIMEOUT)
                        .socketTimeout(SOCKET_TIMEOUT))
                .overrideConfiguration(ClientOverrideConfiguration.builder()
                        .apiCallAttemptTimeout(API_CALL_ATTEMPT_TIMEOUT)
                        .apiCallTimeout(API_CALL_TIMEOUT)
                        .build())
                .build();
    }
}
