FROM grafana/grafana:11.3.0

ENV GF_PATHS_PROVISIONING=/etc/grafana/provisioning \
    GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/citibike-ep3.json

COPY --chown=472:472 provisioning /etc/grafana/provisioning
COPY --chown=472:472 dashboards /var/lib/grafana/dashboards
