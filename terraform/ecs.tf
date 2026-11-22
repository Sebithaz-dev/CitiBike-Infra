# Contrasena del admin de Grafana: se genera en cada entorno y nunca se
# escribe en el repositorio. Se lee con:
#   terraform -chdir=terraform output -raw grafana_admin_password
resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "aws_ecs_cluster" "main" {
  name = "${local.dashboard_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.tags, { Name = "${local.dashboard_name}-cluster" })
}

locals {
  log_groups = {
    dashboard    = "/ecs/${local.dashboard_name}/dashboard"
    prometheus   = "/ecs/${local.dashboard_name}/prometheus"
    grafana      = "/ecs/${local.dashboard_name}/grafana"
    alertmanager = "/ecs/${local.dashboard_name}/alertmanager"
    blackbox     = "/ecs/${local.dashboard_name}/blackbox"
  }

  task_role_arn      = data.aws_iam_role.task.arn
  execution_role_arn = data.aws_iam_role.task.arn
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Service = each.key })
}

# ---------------------------------------------------------------------------
# Dashboard Flask
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "dashboard" {
  family                   = "${local.dashboard_name}-dashboard"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "dashboard"
      image     = "${var.dashboard_image}:${var.image_tag}"
      essential = true
      environment = [
        { name = "FLASK_ENV", value = "production" },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "S3_BUCKET_NAME", value = var.s3_bucket_name },
        { name = "S3_PARQUET_KEY", value = var.s3_parquet_key },
        { name = "S3_MODEL_PREFIX", value = var.s3_model_prefix },
        { name = "GIT_SHA", value = var.image_tag },
      ]
      healthCheck = {
        command = [
          "CMD-SHELL",
          "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5000/health')\"",
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.aws_region
          "awslogs-group"         = aws_cloudwatch_log_group.service["dashboard"].name
          "awslogs-stream-prefix" = "dashboard"
        }
      }
    }
  ])

  tags = merge(local.tags, { Service = "dashboard" })
}

resource "aws_ecs_service" "dashboard" {
  name            = "dashboard"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.dashboard.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Host network + puerto fijo: no se puede solapar una tarea vieja y una nueva.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  health_check_grace_period_seconds = 60

  tags = merge(local.tags, { Service = "dashboard" })

  depends_on = [
    aws_lb_listener.http,
    aws_lb_target_group_attachment.dashboard,
    aws_instance.ecs,
  ]
}

# ---------------------------------------------------------------------------
# Prometheus
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${local.dashboard_name}-prometheus"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = "${var.prometheus_image}:${var.image_tag}"
      essential = true
      command = [
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=6h",
        "--web.enable-lifecycle",
      ]
      environment = [
        { name = "RENDER_HEALTH_URL", value = var.render_health_url },
        { name = "AWS_REGION", value = var.aws_region },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.aws_region
          "awslogs-group"         = aws_cloudwatch_log_group.service["prometheus"].name
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    }
  ])

  tags = merge(local.tags, { Service = "prometheus" })
}

resource "aws_ecs_service" "prometheus" {
  name            = "prometheus"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Host network + puerto fijo: no se puede solapar una tarea vieja y una
  # nueva, asi que el despliegue baja a 0 tareas antes de levantar la nueva.
  # Con los valores por defecto (100/200) el rolling update nunca converge.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, { Service = "prometheus" })

  depends_on = [aws_instance.ecs]
}

# ---------------------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${local.dashboard_name}-grafana"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "${var.grafana_image}:${var.image_tag}"
      essential = true
      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = random_password.grafana_admin.result },
        { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "true" },
        { name = "GF_AUTH_ANONYMOUS_ORG_ROLE", value = "Viewer" },
        { name = "AWS_REGION", value = var.aws_region },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.aws_region
          "awslogs-group"         = aws_cloudwatch_log_group.service["grafana"].name
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  tags = merge(local.tags, { Service = "grafana" })
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Host network + puerto fijo: no se puede solapar una tarea vieja y una
  # nueva, asi que el despliegue baja a 0 tareas antes de levantar la nueva.
  # Con los valores por defecto (100/200) el rolling update nunca converge.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, { Service = "grafana" })

  depends_on = [
    aws_lb_listener.grafana,
    aws_lb_target_group_attachment.grafana,
    aws_instance.ecs,
  ]
}

# ---------------------------------------------------------------------------
# Alertmanager
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "alertmanager" {
  family                   = "${local.dashboard_name}-alertmanager"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  cpu                      = "128"
  memory                   = "256"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "alertmanager"
      image     = "${var.alertmanager_image}:${var.image_tag}"
      essential = true
      command = [
        "--config.file=/etc/alertmanager/alertmanager.yml",
        "--storage.path=/alertmanager",
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.aws_region
          "awslogs-group"         = aws_cloudwatch_log_group.service["alertmanager"].name
          "awslogs-stream-prefix" = "alertmanager"
        }
      }
    }
  ])

  tags = merge(local.tags, { Service = "alertmanager" })
}

resource "aws_ecs_service" "alertmanager" {
  name            = "alertmanager"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.alertmanager.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Host network + puerto fijo: no se puede solapar una tarea vieja y una
  # nueva, asi que el despliegue baja a 0 tareas antes de levantar la nueva.
  # Con los valores por defecto (100/200) el rolling update nunca converge.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, { Service = "alertmanager" })

  depends_on = [aws_instance.ecs]
}

# ---------------------------------------------------------------------------
# Blackbox exporter (disponibilidad del dashboard ECS y de Render)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "blackbox" {
  family                   = "${local.dashboard_name}-blackbox"
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  cpu                      = "128"
  memory                   = "256"
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "blackbox"
      image     = "${var.blackbox_image}:${var.image_tag}"
      essential = true
      command = [
        "--config.file=/etc/blackbox/blackbox.yml",
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.aws_region
          "awslogs-group"         = aws_cloudwatch_log_group.service["blackbox"].name
          "awslogs-stream-prefix" = "blackbox"
        }
      }
    }
  ])

  tags = merge(local.tags, { Service = "blackbox" })
}

resource "aws_ecs_service" "blackbox" {
  name            = "blackbox"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.blackbox.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Host network + puerto fijo: no se puede solapar una tarea vieja y una
  # nueva, asi que el despliegue baja a 0 tareas antes de levantar la nueva.
  # Con los valores por defecto (100/200) el rolling update nunca converge.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, { Service = "blackbox" })

  depends_on = [aws_instance.ecs]
}
