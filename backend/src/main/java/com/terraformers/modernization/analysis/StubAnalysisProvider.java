package com.terraformers.modernization.analysis;

import com.terraformers.modernization.storage.ObjectMetadata;
import com.terraformers.modernization.storage.ObjectReader;
import com.terraformers.modernization.storage.ObjectReference;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnMissingBean(AnalysisProvider.class)
public class StubAnalysisProvider implements AnalysisProvider {

    private final ObjectReader objectReader;

    public StubAnalysisProvider(ObjectReader objectReader) {
        this.objectReader = objectReader;
    }

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
        ObjectMetadata metadata = objectReader.readMetadata(new ObjectReference(
                context.sourceBucket(),
                context.sourceKey()
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

        String preview = "Integrated Java analysis provider boundary is ready. "
                + "source=s3://" + metadata.bucket() + "/" + metadata.key()
                + ", contentType=" + metadata.contentType()
                + ", contentLength=" + metadata.contentLength()
                + ". Replace this stub with Bedrock/OpenSearch adapters.";

        return new AnalysisResult(
                "stub-integrated-java",
                terraformDraft,
                preview,
                List.of("s3://" + metadata.bucket() + "/" + metadata.key())
        );
    }
}
