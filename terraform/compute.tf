resource "aws_instance" "ecs" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.ecs.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  # Registra la instancia en el cluster y habilita credenciales de task role.
  user_data = <<-EOF
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CFG'
    ECS_CLUSTER=${aws_ecs_cluster.main.name}
    ECS_ENABLE_TASK_IAM_ROLE=true
    ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
    CFG
    systemctl restart ecs
  EOF

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.tags, { Name = "${local.dashboard_name}-ecs" })

  depends_on = [aws_ecs_cluster.main]
}

resource "aws_lb_target_group_attachment" "dashboard" {
  target_group_arn = aws_lb_target_group.dashboard.arn
  target_id        = aws_instance.ecs.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.ecs.id
  port             = 3000
}
