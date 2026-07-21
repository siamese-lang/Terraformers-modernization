package com.terraformers.modernization.analysis;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;

@Component
public class AnalysisObservability {
    private final MeterRegistry meterRegistry;
    private final AtomicInteger retrievedHits = new AtomicInteger();

    public AnalysisObservability(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        io.micrometer.core.instrument.Gauge.builder("terraformers.aoss.retrieved_hits", retrievedHits, AtomicInteger::get)
                .register(meterRegistry);
    }

    public MeterRegistry meterRegistry() {
        return meterRegistry;
    }

    public void jobStarted() {
        jobCounter("started", null).increment();
    }

    public void jobSucceeded() {
        jobCounter("succeeded", null).increment();
    }

    public void jobFailed(Throwable exception) {
        jobCounter("failed", category(exception)).increment();
    }

    public Timer.Sample startAnalysis() {
        return Timer.start(meterRegistry);
    }

    public <T> T recordBedrock(Supplier<T> operation) {
        return recordExternal("terraformers.bedrock.invocation", operation);
    }

    public <T> T recordAoss(Supplier<T> operation) {
        return recordExternal("terraformers.aoss.retrieval", operation);
    }

    public void retrievedHits(int count) {
        retrievedHits.set(count);
    }

    private Counter jobCounter(String outcome, String exceptionCategory) {
        Counter.Builder builder = Counter.builder("terraformers.analysis.jobs").tag("outcome", outcome);
        if (exceptionCategory != null) {
            builder.tag("exception_category", exceptionCategory);
        }
        return builder.register(meterRegistry);
    }

    private <T> T recordExternal(String name, Supplier<T> operation) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            T value = operation.get();
            sample.stop(Timer.builder(name).tag("outcome", "success").register(meterRegistry));
            return value;
        } catch (RuntimeException exception) {
            sample.stop(Timer.builder(name).tag("outcome", "failure")
                    .tag("exception_category", category(exception)).register(meterRegistry));
            throw exception;
        }
    }

    private String category(Throwable exception) {
        String simple = exception == null ? "unknown" : exception.getClass().getSimpleName().toLowerCase(Locale.ROOT);
        if (simple.contains("timeout")) return "timeout";
        if (simple.contains("validation")) return "validation";
        if (simple.contains("rejected")) return "rejected_input";
        if (simple.contains("format")) return "response_format";
        if (simple.contains("truncated")) return "truncated_output";
        return "other";
    }
}
