package com.terraformers.modernization.reference;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnMissingBean(ReferenceRetriever.class)
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
