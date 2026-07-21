package com.terraformers.modernization.analysis;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
public class AnalysisExecutorConfig {

    @Bean(name = "analysisJobExecutor")
    @ConditionalOnMissingBean(name = "analysisJobExecutor")
    public ThreadPoolTaskExecutor analysisJobExecutor(MeterRegistry meterRegistry) {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setThreadNamePrefix("analysis-job-");
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(50);
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);

        Counter rejected = Counter.builder("terraformers.analysis.executor.rejections").register(meterRegistry);
        executor.setRejectedExecutionHandler((task, threadPool) -> {
            rejected.increment();
            throw new RejectedExecutionException("analysis executor rejected a task");
        });
        executor.initialize();
        Gauge.builder("terraformers.analysis.executor.queue.depth", executor,
                        taskExecutor -> taskExecutor.getThreadPoolExecutor().getQueue().size())
                .register(meterRegistry);
        return executor;
    }
}
