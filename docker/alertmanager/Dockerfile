FROM prom/alertmanager:v0.27.0

COPY --chown=65534:65534 alertmanager.yml /etc/alertmanager/alertmanager.yml
RUN mkdir -p /alertmanager && chown 65534:65534 /alertmanager
