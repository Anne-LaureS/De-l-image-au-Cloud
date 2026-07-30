# --- Rôle d'EXECUTION -------------------------------------------------------
# Utilisé par l'agent ECS lui-même (avant que le conteneur applicatif ne
# démarre) : pull de l'image sur ECR, écriture des logs dans CloudWatch.
# Le conteneur applicatif n'a JAMAIS accès à ces permissions.
resource "aws_iam_role" "execution" {
  name = "${var.project}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Rôle de TASK (applicatif) ----------------------------------------------
# Utilisé par le processus nginx dans le conteneur pour appeler l'API AWS,
# le cas échéant. Ici la démo statique n'a besoin d'aucun accès AWS :
# le rôle est volontairement vide (pas de policy attachée), ce qui
# matérialise le principe du moindre privilège plutôt que de réutiliser
# le rôle d'exécution par facilité.
resource "aws_iam_role" "task" {
  name = "${var.project}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
