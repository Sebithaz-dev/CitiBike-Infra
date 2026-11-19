variable "aws_region" {
  description = "Region de AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Sufijo de entorno para nombres de recursos"
  type        = string
  default     = "dev"
}

variable "instance_profile_name" {
  description = "Instance profile precreado por el Learner Lab (no se crea IAM)"
  type        = string
  default     = "LabInstanceProfile"
}

variable "task_role_name" {
  description = "Rol de tarea/ejecucion precreado por el Learner Lab"
  type        = string
  default     = "LabRole"
}

variable "instance_type" {
  description = "Tipo de instancia ECS (t3.large: 8 GB para 5 contenedores)"
  type        = string
  default     = "t3.large"
}

variable "s3_bucket_name" {
  description = "Bucket del datalake Citi Bike (default: el del Learner Lab de la EP3)"
  type        = string
  default     = "citibike-datalake-seb-690247773624"
}

variable "s3_parquet_key" {
  description = "Key del parquet curado que consume el dashboard"
  type        = string
  default     = "curated/citibike_trips/citibike_dashboard_sample.parquet"
}

variable "s3_model_prefix" {
  description = "Prefijo de los artefactos del modelo"
  type        = string
  default     = "models/"
}

variable "image_tag" {
  description = "Tag de las imagenes de la aplicacion (SHA del commit o latest)"
  type        = string
  default     = "latest"
}

variable "dashboard_image" {
  description = "Imagen del dashboard Flask"
  type        = string
  default     = "ghcr.io/sebithaz-dev/flask-dashboard-s3"
}

variable "prometheus_image" {
  description = "Imagen de Prometheus con la configuracion horneada"
  type        = string
  default     = "ghcr.io/sebithaz-dev/citibike-prometheus"
}

variable "grafana_image" {
  description = "Imagen de Grafana con provisioning y dashboards"
  type        = string
  default     = "ghcr.io/sebithaz-dev/citibike-grafana"
}

variable "alertmanager_image" {
  description = "Imagen de Alertmanager"
  type        = string
  default     = "ghcr.io/sebithaz-dev/citibike-alertmanager"
}

variable "blackbox_image" {
  description = "Imagen de blackbox-exporter"
  type        = string
  default     = "ghcr.io/sebithaz-dev/citibike-blackbox"
}

variable "render_health_url" {
  description = "URL publica del dashboard en Render para el probe de disponibilidad"
  type        = string
  default     = "https://flask-dashboard-s3.onrender.com/health"
}

variable "log_retention_days" {
  description = "Retencion de CloudWatch Logs (dias)"
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Correo que recibe las alarmas de CloudWatch (vacio = alarmas sin notificacion)"
  type        = string
  default     = ""
}
