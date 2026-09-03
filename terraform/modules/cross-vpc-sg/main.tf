# both rules go directly on the auto-created eks cluster SGs (shared by control plane + nodes)

# sg-to-sg reference across the peering connection
resource "aws_security_group_rule" "backend_allow_from_gateway" {
  type                     = "ingress"
  security_group_id        = var.backend_cluster_security_group_id
  from_port                = var.backend_node_port
  to_port                  = var.backend_node_port
  protocol                 = "tcp"
  source_security_group_id = var.gateway_cluster_security_group_id
  description              = "Backend Service NodePort, gateway cluster only"
}

# only public entry point in the whole setup
resource "aws_security_group_rule" "gateway_allow_public" {
  type              = "ingress"
  security_group_id = var.gateway_cluster_security_group_id
  from_port         = var.gateway_node_port
  to_port           = var.gateway_node_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Public entry point for the gateway proxy Service"
}
