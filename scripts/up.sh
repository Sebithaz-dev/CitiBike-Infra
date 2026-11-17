#!/usr/bin/env bash
# Levanta el entorno ECS completo. Requiere credenciales AWS validas del
# Learner Lab exportadas en el shell (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_SESSION_TOKEN) y terraform instalado.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: credenciales AWS invalidas o expiradas." >&2
  echo "Copia las credenciales de la sesion del Learner Lab y vuelve a intentar." >&2
  exit 1
fi

terraform -chdir=terraform init -input=false
terraform -chdir=terraform apply -input=false -auto-approve

echo
terraform -chdir=terraform output
echo
echo "Grafana: usuario admin / password citibike-ep3"
echo "Recuerda ejecutar ./scripts/down.sh al terminar la sesion."
