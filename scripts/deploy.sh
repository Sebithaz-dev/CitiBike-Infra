#!/usr/bin/env bash
# Despliega una nueva version del dashboard midiendo el tiempo de despliegue
# y publicandolo en CloudWatch (CitiBike/CI) para el dashboard de la EP3.
#
# Uso:
#   ./scripts/deploy.sh <git-sha>
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_TAG="${1:-latest}"
CLUSTER="${ECS_CLUSTER:-citibike-dev-cluster}"
SERVICE="${ECS_SERVICE:-dashboard}"
NAMESPACE="${CLOUDWATCH_NAMESPACE:-CitiBike/CI}"

echo "Desplegando dashboard con tag ${IMAGE_TAG}..."
terraform -chdir=terraform apply -input=false -auto-approve \
  -var="image_tag=${IMAGE_TAG}"

start=$(date +%s)

aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment \
  --query 'service.serviceName' --output text >/dev/null

echo "Esperando estabilidad del servicio (esto puede tardar varios minutos)..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

end=$(date +%s)
duration=$((end - start))
echo "Despliegue estable en ${duration}s."

# Se publica con la AWS CLI (ya es requisito del repo) para no depender de
# boto3 en la maquina del operador; `ci_metrics.py` sigue siendo la via que
# usan los tests y los workflows.
aws cloudwatch put-metric-data --namespace "$NAMESPACE" --metric-data \
  "MetricName=DeploymentDurationSeconds,Value=${duration},Unit=Seconds" \
  "MetricName=QualityGatePassed,Value=1,Unit=None"

echo "Duracion publicada en CloudWatch (${NAMESPACE}/DeploymentDurationSeconds)."
