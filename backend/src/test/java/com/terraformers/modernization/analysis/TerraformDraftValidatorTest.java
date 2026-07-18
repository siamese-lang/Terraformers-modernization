package com.terraformers.modernization.analysis;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class TerraformDraftValidatorTest {
    private final TerraformDraftValidator validator = new TerraformDraftValidator();

    @Test
    void rejectsProviderOnlyTerraform() {
        TerraformDraftValidation validation = validator.validate("""
                terraform { required_version = ">= 1.6" }
                provider "aws" { region = var.aws_region }
                """);
        assertThat(validation.valid()).isFalse();
        assertThat(validation.reason()).contains("resource or module");
    }

    @Test
    void acceptsMultiResourceTerraformDraft() {
        TerraformDraftValidation validation = validator.validate("""
                ```hcl
                provider "aws" { region = var.aws_region }
                resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }
                resource "aws_subnet" "public" { vpc_id = aws_vpc.main.id cidr_block = "10.0.1.0/24" }
                ```
                """);
        assertThat(validation.valid()).isTrue();
        assertThat(validation.sanitizedContent()).doesNotContain("```");
    }
}
