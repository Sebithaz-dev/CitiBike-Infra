resource "aws_instance" "ecs" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.ecs.id]
  iam_instance_profile   = data.aws_iam_instance_profile.lab.name

  # Registra la instancia en el cluster y habilita credenciales de task role.
  #
  # OJO: no usar `systemctl restart ecs` en bloque. Este script corre dentro de
  # cloud-final y ecs.service tiene `After=cloud-final.service`, asi que un
  # restart sincrono espera a que cloud-final termine y cloud-final espera a
  # este script: deadlock y el agente nunca se registra en el cluster.
  # `--no-block` encola el arranque y devuelve el control de inmediato.
  user_data = <<-EOF
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CFG'
    ECS_CLUSTER=${aws_ecs_cluster.main.name}
    ECS_ENABLE_TASK_IAM_ROLE=true
    ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
    CFG
    systemctl enable ecs
    systemctl restart --no-block ecs

    # CloudWatch agent para las metricas de memoria y disco de la instancia
    # (AWS/EC2 solo publica CPU en el monitoreo basico; mem_used_percent y
    # disk_used_percent los aporta el agente en el namespace CWAgent).
    dnf install -y amazon-cloudwatch-agent
    cat > /opt/aws/amazon-cloudwatch-agent/etc/cwagent-ep3.json <<'JSON'
    {
      "agent": { "metrics_collection_interval": 60 },
      "metrics": {
        "namespace": "CWAgent",
        "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
        "metrics_collected": {
          "mem": { "measurement": ["mem_used_percent"] },
          "disk": { "measurement": ["used_percent"], "resources": ["/"] }
        }
      }
    }
    JSON
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/cwagent-ep3.json
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
