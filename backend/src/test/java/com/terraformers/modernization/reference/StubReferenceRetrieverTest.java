package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class StubReferenceRetrieverTest {

    @Test
    void returnsDeterministicReferencesForLocalAndCiVerification() {
        StubReferenceRetriever retriever = new StubReferenceRetriever();

        var documents = retriever.retrieve(ReferenceQuery.fromObject(
                "project-1",
                "example-bucket",
                "uploads/diagram.png",
                "image/png"
        ));

        assertThat(documents)
                .extracting(ReferenceDocument::id)
                .containsExactly("stub-vpc-rds-s3", "stub-sqs-async");
    }
}
