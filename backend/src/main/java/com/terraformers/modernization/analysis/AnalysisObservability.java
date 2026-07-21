package com.terraformers.modernization.analysis;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.Locale;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;

@Component
public class AnalysisObservability {
    private final MeterRegistry meterRegistry;

    public AnalysisObservability(MeterRegistry meterRegistry) { this.meterRegistry = meterRegistry; }
    public Timer.Sample startAnalysis() { return Timer.start(meterRegistry); }
    public void stopAnalysis(Timer.Sample sample) { sample.stop(Timer.builder("terraformers.analysis.duration").register(meterRegistry)); }
    public void jobStarted() { jobs("started").increment(); }
    public void jobSucceeded() { jobs("succeeded").increment(); }
    public void jobFailed(Throwable exception) { jobs("failed").increment(); failures("terraformers.analysis.failures", category(exception)).increment(); }
    public void jobRejected() { jobs("failed").increment(); failures("terraformers.analysis.failures", "executor_rejected").increment(); executorRejections().increment(); }
    public <T> T recordBedrock(Supplier<T> operation) { return recordExternal("terraformers.bedrock", operation); }
    public <T> T recordAoss(Supplier<T> operation) { return recordExternal("terraformers.aoss", operation); }
    public void retrievedHits(int count) { DistributionSummary.builder("terraformers.aoss.retrieved_hits").register(meterRegistry).record(count); }
    private Counter jobs(String outcome) { return Counter.builder("terraformers.analysis.jobs").tag("outcome", outcome).register(meterRegistry); }
    private Counter failures(String name, String category) { return Counter.builder(name).tag("category", category).register(meterRegistry); }
    private Counter executorRejections() { return Counter.builder("terraformers.analysis.executor.rejections").register(meterRegistry); }
    private <T> T recordExternal(String prefix, Supplier<T> operation) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try { T value = operation.get(); Counter.builder(prefix + (prefix.endsWith("bedrock") ? ".invocations" : ".retrievals")).tag("outcome", "success").register(meterRegistry).increment(); return value; }
        catch (RuntimeException exception) { Counter.builder(prefix + (prefix.endsWith("bedrock") ? ".invocations" : ".retrievals")).tag("outcome", "failure").register(meterRegistry).increment(); failures(prefix + ".failures", category(exception)).increment(); throw exception; }
        finally { sample.stop(Timer.builder(prefix + ".duration").register(meterRegistry)); }
    }
    public String category(Throwable exception) {
        if (exception instanceof RejectedExecutionException) return "executor_rejected";
        String simple = exception == null ? "" : exception.getClass().getSimpleName().toLowerCase(Locale.ROOT);
        if (simple.contains("timeout")) return "timeout";
        if (simple.contains("validation")) return "validation";
        if (simple.contains("rejected")) return "rejected_input";
        if (simple.contains("format")) return "response_format";
        if (simple.contains("truncated")) return "truncated_output";
        return "other";
    }
}
