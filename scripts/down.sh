#!/usr/bin/env bash
# Destruye todos los recursos facturables del entorno. Obligatorio al cerrar
# cada sesion del Learner Lab (limite de USD 50).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Esto eliminara el cluster ECS, la instancia, el ALB y los log groups."
read -r -p "Escribe 'destroy' para confirmar: " confirm
if [ "$confirm" != "destroy" ]; then
  echo "Cancelado."
  exit 1
fi

terraform -chdir=terraform destroy -auto-approve

echo "Recursos eliminados. Verifica en la consola que no queden instancias ni ALB."
