package com.terraformers.modernization.config;

import io.micrometer.cloudwatch2.CloudWatchConfig;
import io.micrometer.cloudwatch2.CloudWatchMeterRegistry;
import io.micrometer.core.instrument.Clock;
import io.micrometer.core.instrument.config.MeterFilter;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;

@Configuration
@ConditionalOnProperty(prefix = "management.cloudwatch.metrics.export", name = "enabled", havingValue = "true")
public class CloudWatchMetricsConfiguration {
    @Bean(destroyMethod = "close")
    CloudWatchAsyncClient terraformersCloudWatchAsyncClient(@Value("${AWS_REGION:ap-northeast-2}") String region) {
        return CloudWatchAsyncClient.builder().region(Region.of(region)).build();
    }

    @Bean(destroyMethod = "close")
    CloudWatchMeterRegistry terraformersCloudWatchMeterRegistry(
            CloudWatchAsyncClient client,
            @Value("${management.cloudwatch.metrics.export.namespace:Terraformers/Backend}") String namespace,
            @Value("${management.cloudwatch.metrics.export.step:1m}") Duration step) {
        CloudWatchConfig config = new CloudWatchConfig() {
            @Override public String get(String key) { return null; }
            @Override public String namespace() { return namespace; }
            @Override public Duration step() { return step; }
        };
        CloudWatchMeterRegistry registry = new CloudWatchMeterRegistry(config, Clock.SYSTEM, client);
        registry.config().meterFilter(MeterFilter.denyUnless(id -> id.getName().startsWith("terraformers.")));
        return registry;
    }
}
