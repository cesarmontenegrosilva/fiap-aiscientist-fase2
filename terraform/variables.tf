variable "project_id" {
  type        = string
  description = "ID do projeto GCP"
}

variable "region" {
  type        = string
  description = "Região dos recursos regionais"
  default     = "us-central1"
}

variable "bigquery_location" {
  type        = string
  description = "Localização dos datasets BigQuery. US facilita consultas ao datalake da Base dos Dados."
  default     = "US"
}

variable "bucket_name" {
  type        = string
  description = "Nome globalmente único do bucket"
}

variable "bronze_dataset" {
  type    = string
  default = "alfabetizacao_bronze"
}
variable "silver_dataset" {
  type    = string
  default = "alfabetizacao_silver"
}
variable "gold_dataset" {
  type    = string
  default = "alfabetizacao_gold"
}
variable "monitoring_dataset" {
  type    = string
  default = "alfabetizacao_monitoring"
}
variable "assertions_dataset" {
  type    = string
  default = "alfabetizacao_assertions"
}
variable "pubsub_topic" {
  type    = string
  default = "alfabetizacao-indicadores"
}
variable "pubsub_subscription" {
  type    = string
  default = "alfabetizacao-indicadores-dataflow"
}

variable "billing_account" {
  type        = string
  description = "Conta de faturamento no formato 000000-000000-000000. Vazio desabilita budget via Terraform."
  default     = ""
}


variable "budget_currency" {
  type        = string
  description = "Moeda da conta de faturamento"
  default     = "BRL"
}

variable "monthly_budget_brl" {
  type        = number
  description = "Orçamento mensal de referência em BRL"
  default     = 100
}


variable "allow_destroy_data" {
  type        = bool
  description = "Permite ao terraform destroy remover datasets e bucket não vazios. Mantenha false em uso normal."
  default     = false
}
