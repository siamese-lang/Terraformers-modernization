package com.terraformers.modernization.reference;

import com.terraformers.modernization.analysis.AnalysisRuntimeProperties;
import com.terraformers.modernization.reference.opensearch.OpenSearchReferenceRetriever;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/** Applies the retrieval availability policy around the sole vector retrieval implementation. */
@Component
public class RetrievalModeReferenceRetriever implements ReferenceRetriever {

    private static final Logger log = LoggerFactory.getLogger(RetrievalModeReferenceRetriever.class);

    private final OpenSearchReferenceRetriever vectorRetriever;
    private final AnalysisRuntimeProperties properties;

    public RetrievalModeReferenceRetriever(OpenSearchReferenceRetriever vectorRetriever,
                                           AnalysisRuntimeProperties properties) {
        this.vectorRetriever = vectorRetriever;
        this.properties = properties;
    }

    @Override
    public List<ReferenceDocument> retrieve(ReferenceQuery query) {
        RetrievalMode mode = properties.getRetrievalMode();
        if (mode == null) {
            throw new IllegalStateException("terraformers.analysis.retrieval-mode must be set");
        }
        if (mode == RetrievalMode.DISABLED) {
            log.info("reference retrieval outcome=disabled mode={}", mode);
            return List.of();
        }
        long started = System.nanoTime();
        try {
            List<ReferenceDocument> documents = vectorRetriever.retrieve(query);
            if (mode == RetrievalMode.REQUIRED && documents.isEmpty()) {
                throw new IllegalStateException("required reference retrieval returned no documents");
            }
            log.info("reference retrieval outcome={} mode={} modelId={} index={} topK={} hitCount={} documentIds={} elapsedMs={}",
                    documents.isEmpty() ? "empty" : "success", mode,
                    properties.getBedrockEmbeddingModelId(), properties.getIndexName(), properties.getOpensearchTopK(),
                    documents.size(), documents.stream().map(ReferenceDocument::id).toList(), elapsedMillis(started));
            return documents;
        } catch (RuntimeException exception) {
            log.warn("reference retrieval outcome=failure mode={} stage=search modelId={} index={} topK={} errorClass={} elapsedMs={}",
                    mode, properties.getBedrockEmbeddingModelId(), properties.getIndexName(), properties.getOpensearchTopK(),
                    exception.getClass().getName(), elapsedMillis(started));
            if (mode == RetrievalMode.REQUIRED) {
                throw exception;
            }
            return List.of();
        }
    }

    private long elapsedMillis(long started) {
        return (System.nanoTime() - started) / 1_000_000;
    }
}
