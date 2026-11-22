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

   El bucket del datalake tiene un default (`citibike-datalake-seb-690247773624`).
   Para usar otro: `export TF_VAR_s3_bucket_name=otro-bucket` antes de `up.sh`.

## Verificación

`verify.sh` valida todo el entorno y devuelve exit code distinto de 0 si algo
falla, así que sirve como evidencia reproducible:

```bash
./scripts/verify.sh          # estado actual
./scripts/verify.sh --wait   # espera servicios estables antes de validar
```

Comprueba: 5 servicios ECS (`ACTIVE` y `running == desired`), target groups
`healthy`, `/health`, `/`, `/metrics` del dashboard, `/api/health` de Grafana,
la salud de los datasources (Prometheus y CloudWatch, este último vía task
role) y que el dashboard `citibike-ep3` tenga sus 5 filas.

Equivalente manual:

```bash
aws ecs describe-services \
  --cluster citibike-dev-cluster \
  --services dashboard prometheus grafana alertmanager blackbox \
  --query 'services[].[serviceName,status,runningCount,desiredCount]' --output table

curl -fsS "$(terraform -chdir=terraform output -raw dashboard_url)/health"
curl -fsS "$(terraform -chdir=terraform output -raw dashboard_url)/metrics" | head
```

Abrir Grafana en `http://<alb-dns>:3000` y revisar las cinco filas del dashboard `CitiBike EP3`.

### Evidencia para el informe

`collect_evidence.sh` ejecuta la verificación y guarda todo lo que el informe
necesita en `docs/evidence/<fecha>/` (servicios ECS, target groups, HTTP,
targets y reglas de Prometheus, alarmas y métricas de CloudWatch y la auditoría
de cumplimiento de los tres repos):

```bash
./scripts/collect_evidence.sh
```

### Alarmas y auditoría

Las alarmas de CloudWatch se crean con Terraform (`terraform/monitoring.tf`) y
se consultan así:

```bash
aws cloudwatch describe-alarms --alarm-name-prefix citibike-dev \
  --query 'MetricAlarms[].[AlarmName,StateValue,MetricName]' --output table

python3 scripts/audit_compliance.py --strict      # auditoría de gobierno (IE5)
```

Con `alarm_email` en `terraform/terraform.tfvars` (o `TF_VAR_alarm_email=tu@correo.cl`)
las alarmas envían correo al pasar a `ALARM` y al volver a `OK`. Hay que
confirmar la suscripción SNS una vez por entorno; `up.sh` avisa si falta.

## Problemas comunes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `up.sh` falla con "credenciales invalidas" | Token expirado o credenciales copiadas de una sesión anterior | Terminar e iniciar de nuevo el laboratorio, esperar el punto verde, abrir **AWS Details** y copiar los tres valores recién emitidos; validar con `aws sts get-caller-identity` |
| ECS no puede descargar la imagen (`CannotPullContainerError`) | Paquete de GHCR privado | Las 6 imágenes deben ser públicas (`https://github.com/users/Sebithaz-dev/packages`) |
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
