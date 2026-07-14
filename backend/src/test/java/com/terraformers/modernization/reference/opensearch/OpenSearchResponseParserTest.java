package com.terraformers.modernization.reference.opensearch;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.terraformers.modernization.reference.ReferenceDocument;
import java.util.List;
import org.junit.jupiter.api.Test;

class OpenSearchResponseParserTest {

    private final OpenSearchResponseParser parser = new OpenSearchResponseParser(new ObjectMapper());

    @Test
    void parsesReferenceDocumentsFromHits() {
        String response = """
                {
                  "hits": {
                    "hits": [
                      {
                        "_id": "doc-1",
                        "_score": 1.23,
                        "_source": {
                          "id": "reference-vpc",
                          "title": "VPC baseline",
                          "content": "Use private subnets for backend workloads."
                        }
                      }
                    ]
                  }
                }
                """;

        List<ReferenceDocument> documents = parser.parse(response, "content");

        assertThat(documents).hasSize(1);
        assertThat(documents.get(0).id()).isEqualTo("reference-vpc");
        assertThat(documents.get(0).title()).isEqualTo("VPC baseline");
        assertThat(documents.get(0).content()).contains("private subnets");
        assertThat(documents.get(0).score()).isEqualTo(1.23);
    }
}
