output "alb_dns_name" {
  description = "DNS publico del ALB"
  value       = aws_lb.main.dns_name
}

output "dashboard_url" {
  description = "URL del dashboard Flask"
  value       = "http://${aws_lb.main.dns_name}"
}

output "grafana_url" {
  description = "URL de Grafana (usuario admin / password citibike-ep3)"
  value       = "http://${aws_lb.main.dns_name}:3000"
}

output "prometheus_internal_url" {
  description = "Prometheus solo escucha en la instancia (no expuesto por el ALB)"
  value       = "http://${aws_instance.ecs.private_ip}:9090"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_instance_id" {
  value = aws_instance.ecs.id
}

output "log_groups" {
  value = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}
