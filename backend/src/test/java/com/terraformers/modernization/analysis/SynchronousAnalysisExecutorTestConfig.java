package com.terraformers.modernization.analysis;

import java.util.concurrent.Executor;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.core.task.SyncTaskExecutor;

@TestConfiguration
public class SynchronousAnalysisExecutorTestConfig {

    @Bean(name = "analysisJobExecutor")
    @Primary
    public Executor analysisJobExecutor() {
        return new SyncTaskExecutor();
    }
}
