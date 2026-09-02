variable "gateway_cluster_security_group_id" {
  type = string
}

variable "backend_cluster_security_group_id" {
  type = string
}

variable "gateway_node_port" {
  description = "Fixed NodePort the public gateway Service listens on. Opened to the internet - this is the intended public entry point."
  type        = number
}

variable "backend_node_port" {
  description = "Fixed NodePort the internal backend Service listens on. Opened only to the gateway cluster's security group, never to the internet."
  type        = number
}
