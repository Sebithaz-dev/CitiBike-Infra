# Politica de seguridad

## Reportar una vulnerabilidad

No abras un issue publico. Usa **Security > Report a vulnerability** en este
repositorio o escribe a `sebithaz-dev@users.noreply.github.com`.

## Controles de este repositorio

| Control | Implementacion |
|---|---|
| IAM | No se crean roles ni politicas; se reutilizan `LabRole` y `LabInstanceProfile` |
| Instancia | IMDSv2 obligatorio, EBS cifrado, sin contenedores privilegiados |
| Red | Solo el ALB expone puertos; Prometheus/Alertmanager/blackbox quedan en el host |
| Logs | CloudWatch Logs con retencion de 7 dias |
| Dependencias | Dependabot + `.github/dependabot.yml` |
| Secretos | GitHub secret scanning + push protection |
| IaC | `terraform fmt -check` y `validate` en cada PR |
| Configuracion | `promtool check config/rules`, `amtool check-config` y validacion del dashboard JSON |

Las credenciales del Learner Lab son temporales y **nunca** se guardan en el
repositorio ni en la imagen. Se inyectan por variables de entorno al ejecutar
`scripts/up.sh`.
