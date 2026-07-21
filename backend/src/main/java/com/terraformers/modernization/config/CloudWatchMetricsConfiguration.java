package com.terraformers.modernization.config;

import io.micrometer.core.instrument.config.MeterFilter;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import io.micrometer.cloudwatch2.CloudWatchMeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class CloudWatchMetricsConfiguration {

    @Bean
    MeterRegistryCustomizer<CloudWatchMeterRegistry> terraformersCloudWatchMetricFilter() {
        return registry -> registry.config().meterFilter(MeterFilter.denyUnless(
                meterId -> meterId.getName().startsWith("terraformers.")));
    }
}
