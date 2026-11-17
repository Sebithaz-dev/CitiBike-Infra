# Runbook — CitiBike Infra

## Inicio de sesión (Learner Lab)

1. Iniciar el laboratorio y copiar las credenciales temporales.
2. Exportarlas en el shell:

   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_SESSION_TOKEN=...
   export AWS_REGION=us-east-1
   aws sts get-caller-identity
   ```

3. Verificar el tag de las imágenes en GHCR:

   ```bash
   gh api /users/Sebithaz-dev/packages/container/citibike-prometheus/versions --jq '.[0].metadata.container.tags'
   ```

4. Levantar la infraestructura:

   ```bash
   ./scripts/up.sh
   ```

## Verificación

```bash
aws ecs describe-services \
  --cluster citibike-dev-cluster \
  --services dashboard prometheus grafana alertmanager blackbox \
  --query 'services[].[serviceName,status,runningCount,desiredCount]' --output table

curl -fsS "$(terraform -chdir=terraform output -raw dashboard_url)/health"
curl -fsS "$(terraform -chdir=terraform output -raw dashboard_url)/metrics" | head
```

Abrir Grafana en `http://<alb-dns>:3000` y revisar las cuatro filas del dashboard `CitiBike EP3`.

## Problemas comunes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `up.sh` falla con "credenciales invalidas" | Token expirado | Reiniciar la sesión del laboratorio y reexportar |
| Servicio en `ACTIVE` con `runningCount=0` | Imagen inexistente o error de arranque | `aws ecs describe-tasks`, revisar CloudWatch Logs del servicio |
| Dashboard 502 en el ALB | Contenedor aún arrancando o `/health` falla | Esperar 60 s; revisar `dashboard` logs |
| Grafana sin datos de CloudWatch | Task role sin permisos o región incorrecta | Verificar `LabRole` y `AWS_REGION`; revisar logs de Grafana |
| Prometheus no scrapea el dashboard | Servicio caído o puerto 5000 no escuchando | `up{job="dashboard"}` en Prometheus y logs de ECS |

## Cierre de sesión

```bash
./scripts/down.sh
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output table
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
```

No debe quedar ninguna instancia, ALB ni cluster activo.
