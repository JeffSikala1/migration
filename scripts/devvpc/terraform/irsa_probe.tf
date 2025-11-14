# Toggle the probe on/off if you like
variable "enable_irsa_probe" {
  type        = bool
  default     = true
  description = "Run a one-off Job to validate IRSA can call STS and CodeArtifact."
}

resource "kubernetes_job" "irsa_probe" {
  count = var.enable_irsa_probe ? 1 : 0

  metadata {
    name      = "irsa-probe"
    namespace = var.irsa_namespace        # e.g., "ingress-nginx"
    labels = { app = "irsa-probe" }
  }

  spec {
    ttl_seconds_after_finished = 600
    backoff_limit              = 0

    template {
      metadata { labels = { app = "irsa-probe" } }
      spec {
        service_account_name = var.irsa_service_account   # e.g., "codeartifact-deployer"
        restart_policy       = "Never"

        container {
          name  = "probe"
          image = "public.ecr.aws/aws-cli/aws-cli:latest"
          command = ["/bin/sh","-lc"]
          args = [<<-SCRIPT
            set -euo pipefail
            echo "=== STS caller identity ==="
            aws sts get-caller-identity

            echo "=== CodeArtifact token (first 12 chars) ==="
            aws codeartifact get-authorization-token \
              --domain "${var.codeartifact_domain}" \
              --domain-owner "${var.codeartifact_account}" \
              --region "${var.region}" \
              --query authorizationToken --output text | cut -c1-12
          SCRIPT
          ]
          env {
            name  = "AWS_REGION"
            value = var.region
          }
        }
      }
    }
  }

  # Make sure the SA/role exist before running
  depends_on = [
    aws_iam_role.irsa,
    aws_iam_role_policy_attachment.attach_read,
    kubernetes_service_account.codeartifact_deployer
  ]
}