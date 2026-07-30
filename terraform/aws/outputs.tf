output "ecr_repository_url" {
  value = aws_ecr_repository.demo_web.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "task_public_ip_hint" {
  description = "L'IP publique de la tâche est dynamique (Fargate) : la récupérer via `aws ecs list-tasks` + `aws ecs describe-tasks` après déploiement, ou attacher un ALB pour une URL stable."
  value       = "voir README / rapport"
}
