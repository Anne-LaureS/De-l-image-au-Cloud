variable "aws_region" {
  description = "Région AWS de déploiement"
  type        = string
  default     = "eu-west-3"
}

variable "project" {
  description = "Préfixe de nommage des ressources"
  type        = string
  default     = "bc-demo-web"
}

variable "image_digest" {
  description = <<-EOT
    Digest complet de l'image poussée sur ECR, format :
    <account_id>.dkr.ecr.<region>.amazonaws.com/bc/demo-web@sha256:<digest>
    Obligatoire : on référence l'image par digest, jamais par tag,
    pour garantir l'immutabilité de ce qui est réellement déployé
    (cf. incident tj-actions dans le rapport).
  EOT
  type        = string
}

variable "container_port" {
  description = "Port exposé par le conteneur nginx non-root"
  type        = number
  default     = 8080
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}
