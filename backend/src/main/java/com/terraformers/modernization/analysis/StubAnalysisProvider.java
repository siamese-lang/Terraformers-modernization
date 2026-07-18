package com.terraformers.modernization.analysis;

import com.terraformers.modernization.reference.ReferenceDocument;
import com.terraformers.modernization.reference.ReferenceQuery;
import com.terraformers.modernization.reference.ReferenceRetriever;
import com.terraformers.modernization.storage.ObjectMetadata;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "bedrock-provider-enabled", havingValue = "false", matchIfMissing = true)
public class StubAnalysisProvider implements AnalysisProvider {

    private final ObjectReader objectReader;
    private final ReferenceRetriever referenceRetriever;

    public StubAnalysisProvider(ObjectReader objectReader, ReferenceRetriever referenceRetriever) {
        this.objectReader = objectReader;
        this.referenceRetriever = referenceRetriever;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        ObjectMetadata metadata = objectReader.readMetadata(new ObjectReference(
                context.sourceBucket(),
                context.sourceKey()
        ));

        List<ReferenceDocument> references = referenceRetriever.retrieve(ReferenceQuery.fromObject(
                context.projectId(),
                metadata.bucket(),
                metadata.key(),
                metadata.contentType()
        ));

        String terraformDraft = """
                terraform {
                  required_providers {
                    aws = {
                      source  = \"hashicorp/aws\"
                      version = \"~> 5.0\"
                    }
                  }
                }

                provider \"aws\" {
                  region = var.aws_region
                }
                """;

        String explanation = "Integrated Java analysis provider boundary is ready. "
                + "source=s3://" + metadata.bucket() + "/" + metadata.key()
                + ", contentType=" + metadata.contentType()
                + ", contentLength=" + metadata.contentLength()
                + ", references=" + references.size()
                + ". Replace this stub with Bedrock/OpenSearch adapters.";

        return new AnalysisResult(
                "stub-integrated-java",
                terraformDraft,
                explanation,
                List.of("S3 artifact bucket", "SQS analysis event queue"),
                List.of("analysis events are published to the queue after artifacts are persisted"),
                List.of("Stub output is for local verification only; enable Bedrock for real image analysis."),
                references.stream().map(ReferenceDocument::id).toList()
        );
    }
}
