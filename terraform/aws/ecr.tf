resource "aws_ecr_repository" "demo_web" {
  name = "bc/demo-web"

  # Empêche l'écrasement d'un tag existant : un "docker push" sur un tag
  # déjà publié échoue (ImageTagAlreadyExistsException). C'est la
  # protection directe contre le scénario tj-actions/changed-files
  # (retag malveillant d'une release existante) — cf. rapport, partie B.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  force_delete = false

  tags = {
    Project = var.project
    TP      = "TP3-module4"
  }
}

# Politique de cycle de vie : purge les images non taguées après 14 jours
# (bonne pratique, hors périmètre strict du TP mais pertinente en prod)
resource "aws_ecr_lifecycle_policy" "demo_web" {
  repository = aws_ecr_repository.demo_web.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      }
    ]
  })
}
