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
        if (mode == RetrievalMode.DISABLED) {
            log.info("reference retrieval outcome=disabled mode={} projectId={}", mode, query.projectId());
            return List.of();
        }
        long started = System.nanoTime();
        try {
            List<ReferenceDocument> documents = vectorRetriever.retrieve(query);
            if (mode == RetrievalMode.REQUIRED && documents.isEmpty()) {
                throw new IllegalStateException("required reference retrieval returned no documents");
            }
            log.info("reference retrieval outcome={} mode={} projectId={} modelId={} index={} topK={} hitCount={} documentIds={} elapsedMs={}",
                    documents.isEmpty() ? "empty" : "success", mode, query.projectId(),
                    properties.getBedrockEmbeddingModelId(), properties.getIndexName(), properties.getOpensearchTopK(),
                    documents.size(), documents.stream().map(ReferenceDocument::id).toList(), elapsedMillis(started));
            return documents;
        } catch (RuntimeException exception) {
            if (mode == RetrievalMode.REQUIRED) {
                throw exception;
            }
            log.warn("reference retrieval outcome=failure mode={} projectId={} errorClass={} elapsedMs={}",
                    mode, query.projectId(), exception.getClass().getName(), elapsedMillis(started));
            return List.of();
        }
    }

    private long elapsedMillis(long started) {
        return (System.nanoTime() - started) / 1_000_000;
    }
}
