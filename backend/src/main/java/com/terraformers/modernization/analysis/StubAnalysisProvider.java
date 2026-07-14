package com.terraformers.modernization.analysis;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnMissingBean(AnalysisProvider.class)
public class StubAnalysisProvider implements AnalysisProvider {

    @Override
    public AnalysisResult analyze(AnalysisRequestContext context) {
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

        return new AnalysisResult(
                "stub-integrated-java",
                terraformDraft,
                "Integrated Java analysis provider boundary is ready. Replace this stub with Bedrock/OpenSearch adapters.",
                List.of("s3://" + context.sourceBucket() + "/" + context.sourceKey())
        );
    }
}
