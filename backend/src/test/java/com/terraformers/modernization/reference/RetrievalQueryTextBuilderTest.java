package com.terraformers.modernization.reference;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;

class RetrievalQueryTextBuilderTest {
    @Test
    void buildsCorpusIndependentArchitectureQueryWithoutSourceMetadata() {
        String query = new RetrievalQueryTextBuilder().build(new ArchitectureRetrievalFacts(
                "private EKS workload with managed database", List.of("EKS", "RDS", "VPC"),
                List.of("EKS workloads connect to RDS in private subnets"), List.of("aws_eks_cluster", "aws_db_instance")));

        assertThat(query).contains("EKS", "RDS", "aws_eks_cluster")
                .doesNotContain("project-", "bucket", "key", "https://", "pdf", "page");
    }
}
