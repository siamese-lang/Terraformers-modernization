resource "aws_security_group" "aoss_vpc_endpoint" {
  lifecycle {
    # Ingress is owned exclusively by the standalone
    # aws_vpc_security_group_ingress_rule resources in main.tf.
    ignore_changes = [ingress]
  }
}
