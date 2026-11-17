#!/bin/sh
# Renderiza la configuracion sustituyendo la URL publica de Render y arranca
# Prometheus con los argumentos que recibe del task definition.
set -eu

RENDER_HEALTH_URL="${RENDER_HEALTH_URL:-https://flask-dashboard-s3.onrender.com/health}"

sed "s|__RENDER_HEALTH_URL__|${RENDER_HEALTH_URL}|g" \
  /etc/prometheus/prometheus.yml.tmpl > /etc/prometheus/prometheus.yml

exec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml "$@"
