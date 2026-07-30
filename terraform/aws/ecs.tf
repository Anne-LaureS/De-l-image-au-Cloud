resource "aws_ecs_cluster" "this" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.project}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn             = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "web"
      # Référence par DIGEST, jamais par tag mutable/roulant.
      image = var.image_digest

      essential = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      # --- Durcissement runtime (chapitre 5) -----------------------------
      readonlyRootFilesystem = true
      user                    = "101:101" # uid/gid nginx non-root de l'image
      privileged              = false

      linuxParameters = {
        capabilities = {
          drop = ["ALL"]
        }
      }

      # tmpfs nécessaires car le rootfs est en lecture seule : nginx doit
      # pouvoir écrire son cache, ses fichiers temporaires et son pid.
      mountPoints = [
        { sourceVolume = "tmp", containerPath = "/tmp", readOnly = false },
        { sourceVolume = "cache", containerPath = "/var/cache/nginx", readOnly = false },
        { sourceVolume = "run", containerPath = "/var/run", readOnly = false }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])

  volume {
    name = "tmp"
  }
  volume {
    name = "cache"
  }
  volume {
    name = "run"
  }
}

resource "aws_ecs_service" "web" {
  name            = "${var.project}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = true # démo : IP publique directe (alternative : ALB privé)
  }
}
