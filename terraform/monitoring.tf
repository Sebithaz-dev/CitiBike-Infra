# Alarmas de CloudWatch para la EP3.
#
# Complementan a las reglas de Prometheus (que cubren el microservicio desde
# dentro) con la vision de la infraestructura: disponibilidad en el ALB, tasa
# de errores 5xx, latencia, CPU/memoria de la instancia y resultado de los
# quality gates del pipeline.
#
# Sin `alarm_email` las alarmas no tienen accion asociada (solo cambian de
# estado y quedan visibles en la consola / Grafana). Con `alarm_email` se crea
# un topic SNS y una suscripcion por correo que hay que confirmar una vez.

locals {
  alb_arn_suffix = aws_lb.main.arn_suffix
  alarm_actions  = var.alarm_email == "" ? [] : [aws_sns_topic.alarms[0].arn]
}

resource "aws_sns_topic" "alarms" {
  count = var.alarm_email == "" ? 0 : 1

  name = "${local.dashboard_name}-alarms"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- Disponibilidad ---------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dashboard_unhealthy" {
  alarm_name        = "${local.dashboard_name}-dashboard-unhealthy"
  alarm_description = "El target group del dashboard no tiene hosts sanos: el microservicio esta caido o no responde el health check."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"
  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.dashboard.arn_suffix
  }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# --- Errores y latencia -----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name        = "${local.dashboard_name}-target-5xx"
  alarm_description = "El dashboard devuelve mas de 5 respuestas 5xx en 5 minutos."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.dashboard.arn_suffix
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name        = "${local.dashboard_name}-latency-p95"
  alarm_description = "La latencia p95 del dashboard supera 1.5 s durante 3 minutos seguidos."

  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"
  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = aws_lb_target_group.dashboard.arn_suffix
  }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1.5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}

# --- Recursos ---------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "instance_cpu" {
  alarm_name        = "${local.dashboard_name}-instance-cpu"
  alarm_description = "La instancia ECS supera 85 % de CPU durante 15 minutos."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  dimensions = {
    InstanceId = aws_instance.ecs.id
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "instance_memory" {
  alarm_name        = "${local.dashboard_name}-instance-memory"
  alarm_description = "La instancia ECS supera 85 % de memoria usada durante 15 minutos (metrica publicada por el CloudWatch agent)."

  namespace   = "CWAgent"
  metric_name = "mem_used_percent"
  dimensions = {
    InstanceId = aws_instance.ecs.id
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}

# --- Quality gates del pipeline ---------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ci_gate_failed" {
  alarm_name        = "${local.dashboard_name}-ci-gate-failed"
  alarm_description = "El ultimo quality gate del pipeline CI fallo (QualityGatePassed = 0 en CitiBike/CI)."

  namespace   = "CitiBike/CI"
  metric_name = "QualityGatePassed"
  statistic   = "Minimum"
  period      = 300
  # 12 periodos = 1 hora: si el gate se publica una vez por sesion, la alarma
  # no se dispara por falta de datos dentro de la misma hora.
  evaluation_periods  = 12
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "model_gate_failed" {
  alarm_name        = "${local.dashboard_name}-model-gate-failed"
  alarm_description = "El quality gate del modelo no aprobo (QualityGatePassed = 0 en CitiBike/Model)."

  namespace           = "CitiBike/Model"
  metric_name         = "QualityGatePassed"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 12
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = local.alarm_actions
}
