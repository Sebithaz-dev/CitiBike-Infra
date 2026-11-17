FROM prom/prometheus:v2.55.1

COPY --chown=65534:65534 prometheus.yml.tmpl /etc/prometheus/prometheus.yml.tmpl
COPY --chown=65534:65534 alerts.yml /etc/prometheus/alerts.yml
COPY --chown=65534:65534 entrypoint.sh /entrypoint.sh

USER root
RUN chmod 0755 /entrypoint.sh && mkdir -p /prometheus && chown 65534:65534 /prometheus
USER 65534

ENTRYPOINT ["/entrypoint.sh"]
