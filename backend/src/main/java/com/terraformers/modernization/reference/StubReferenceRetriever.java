package com.terraformers.modernization.reference;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "terraformers.analysis", name = "opensearch-retriever-enabled", havingValue = "false", matchIfMissing = true)
public class StubReferenceRetriever implements ReferenceRetriever {

    @Override
    public List<ReferenceDocument> retrieve(ReferenceQuery query) {
        return List.of(
                new ReferenceDocument(
                        "stub-vpc-rds-s3",
                        "AWS reference pattern: VPC, RDS, S3",
                        "Use VPC networking, managed relational storage, and object storage metadata separation.",
                        1.0
                ),
                new ReferenceDocument(
                        "stub-sqs-async",
                        "AWS reference pattern: SQS async progress",
                        "Use SQS to decouple long-running analysis progress and result delivery.",
                        0.8
                )
        );
    }
}
