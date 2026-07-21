package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenSearchResponseParserTest {

    private final OpenSearchResponseParser parser = new OpenSearchResponseParser(new ObjectMapper());

    @Test
    void parsesLogicalIdAndReferenceMetadataFromHits() {
        String response = """
                {
                  "hits": {
                    "hits": [
                      {
                        "_id": "generated-opensearch-id",
                        "_score": 1.23,
                        "_source": {
                          "documentId": "tfaws-5.100.0-aws_vpc-schema",
                          "title": "aws_vpc - provider schema",
                          "content": "Provider schema content.",
                          "documentType": "AWS_PROVIDER_SCHEMA",
                          "resourceTypes": ["aws_vpc"],
                          "sourcePath": "terraform providers schema -json#resource_schemas.aws_vpc",
                          "providerVersion": "5.100.0",
                          "corpusVersion": "terraformers-reference-v2",
                          "authority": "PROVIDER_SCHEMA",
                          "priority": 70,
                          "riskTags": ["public-cidr"]
                        }
                      }
                    ]
                  }
                }
                """;

        List<ReferenceDocument> documents = parser.parse(response, "content");

        assertThat(documents).hasSize(1);
        ReferenceDocument document = documents.get(0);
        assertThat(document.id()).isEqualTo("tfaws-5.100.0-aws_vpc-schema");
        assertThat(document.title()).isEqualTo("aws_vpc - provider schema");
        assertThat(document.content()).contains("Provider schema");
        assertThat(document.score()).isEqualTo(1.23);
        assertThat(document.documentType()).isEqualTo("AWS_PROVIDER_SCHEMA");
        assertThat(document.resourceTypes()).containsExactly("aws_vpc");
        assertThat(document.sourcePath()).contains("resource_schemas.aws_vpc");
        assertThat(document.providerVersion()).isEqualTo("5.100.0");
        assertThat(document.corpusVersion()).isEqualTo("terraformers-reference-v2");
        assertThat(document.authority()).isEqualTo("PROVIDER_SCHEMA");
        assertThat(document.priority()).isEqualTo(70);
        assertThat(document.riskTags()).containsExactly("public-cidr");
    }
}
