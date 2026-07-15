locals {
  services = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "compute.googleapis.com",
    "dataflow.googleapis.com",
    "dataform.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com"
  ])

  labels = {
    project     = "alfabetizacao"
    environment = "academic"
    managed_by  = "terraform"
  }
}


# Obtém informações do projeto GCP existente.
# O número interno do projeto será usado no orçamento.
data "google_project" "current" {
  project_id = var.project_id
}


# Habilita todas as APIs necessárias para a aplicação.
resource "google_project_service" "apis" {
  for_each = local.services

  project = var.project_id
  service = each.value

  # Mantém as APIs habilitadas caso o Terraform seja destruído.
  disable_on_destroy = false
}


# Cria o bucket usado como Data Lake.
resource "google_storage_bucket" "lake" {
  name     = var.bucket_name
  project  = var.project_id
  location = var.bigquery_location

  # Impede permissões individuais por objeto.
  uniform_bucket_level_access = true

  # Permite apagar o bucket mesmo que ele contenha arquivos.
  force_destroy = var.allow_destroy_data

  labels = local.labels

  # Mantém versões anteriores dos objetos.
  versioning {
    enabled = true
  }

  # Exclui arquivos temporários após 30 dias.
  lifecycle_rule {
    condition {
      age = 30

      matches_prefix = [
        "tmp/",
        "staging/"
      ]
    }

    action {
      type = "Delete"
    }
  }

  # Move dados antigos da Bronze para armazenamento mais barato.
  lifecycle_rule {
    condition {
      age = 90

      matches_prefix = [
        "bronze/"
      ]
    }

    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  depends_on = [
    google_project_service.apis
  ]
}


# Cria os datasets do BigQuery.
resource "google_bigquery_dataset" "datasets" {
  for_each = {
    bronze     = var.bronze_dataset
    silver     = var.silver_dataset
    gold       = var.gold_dataset
    monitoring = var.monitoring_dataset
    assertions = var.assertions_dataset
  }

  project    = var.project_id
  dataset_id = each.value

  friendly_name = "Alfabetização ${title(each.key)}"

  description = "Camada ${each.key} do Tech Challenge de alfabetização"

  location = var.bigquery_location

  # Permite excluir as tabelas quando terraform destroy for executado.
  delete_contents_on_destroy = var.allow_destroy_data

  labels = merge(
    local.labels,
    {
      layer = each.key
    }
  )

  depends_on = [
    google_project_service.apis
  ]
}


# Cria a tabela que recebe os eventos válidos do streaming.
resource "google_bigquery_table" "stream_valid" {
  project = var.project_id

  dataset_id = google_bigquery_dataset.datasets["bronze"].dataset_id

  table_id = "eventos_indicador"

  description = "Eventos válidos recebidos por Pub/Sub e Dataflow"

  deletion_protection = false

  schema = file(
    "${path.module}/schemas/eventos_indicador.json"
  )

  # Melhora consultas por UF e município.
  clustering = [
    "sigla_uf",
    "id_municipio"
  ]

  # Particiona os dados pela data do evento.
  time_partitioning {
    type  = "DAY"
    field = "data_evento"
  }

  labels = merge(
    local.labels,
    {
      layer     = "bronze"
      ingestion = "streaming"
    }
  )
}


# Cria a tabela que recebe eventos inválidos.
resource "google_bigquery_table" "stream_rejected" {
  project = var.project_id

  dataset_id = google_bigquery_dataset.datasets["bronze"].dataset_id

  table_id = "eventos_rejeitados"

  description = "Dead-letter analítico de eventos inválidos"

  deletion_protection = false

  schema = file(
    "${path.module}/schemas/eventos_rejeitados.json"
  )

  # Particiona os registros pela data do processamento.
  time_partitioning {
    type  = "DAY"
    field = "data_processamento"
  }

  labels = merge(
    local.labels,
    {
      layer     = "bronze"
      ingestion = "streaming"
    }
  )
}


# Cria o tópico Pub/Sub.
resource "google_pubsub_topic" "indicator" {
  name    = var.pubsub_topic
  project = var.project_id

  # Mantém mensagens por 24 horas.
  message_retention_duration = "86400s"

  labels = local.labels

  depends_on = [
    google_project_service.apis
  ]
}


# Cria a assinatura utilizada pelo Dataflow.
resource "google_pubsub_subscription" "dataflow" {
  name    = var.pubsub_subscription
  project = var.project_id

  topic = google_pubsub_topic.indicator.id

  # Tempo máximo para confirmar o processamento da mensagem.
  ack_deadline_seconds = 60

  # Mantém mensagens não processadas por sete dias.
  message_retention_duration = "604800s"

  retain_acked_messages = false

  # Remove automaticamente a assinatura após longo período sem uso.
  expiration_policy {
    ttl = "2678400s"
  }

  # Configura novas tentativas em caso de erro.
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.labels
}


# Conta de serviço usada pela ingestão batch.
resource "google_service_account" "batch" {
  project = var.project_id

  account_id = "alfabetizacao-batch"

  display_name = "Tech Challenge - Batch Ingestion"

  depends_on = [
    google_project_service.apis
  ]
}


# Conta de serviço utilizada pelos workers do Dataflow.
resource "google_service_account" "dataflow" {
  project = var.project_id

  account_id = "alfabetizacao-dataflow"

  display_name = "Tech Challenge - Dataflow Worker"

  depends_on = [
    google_project_service.apis
  ]
}


# Permissões da conta de serviço do pipeline batch.
resource "google_project_iam_member" "batch_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/logging.logWriter",
    "roles/storage.objectAdmin"
  ])

  project = var.project_id

  role = each.value

  member = "serviceAccount:${google_service_account.batch.email}"
}


# Permissões da conta de serviço do Dataflow.
resource "google_project_iam_member" "dataflow_roles" {
  for_each = toset([
    "roles/dataflow.worker",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.subscriber",
    "roles/storage.objectAdmin"
  ])

  project = var.project_id

  role = each.value

  member = "serviceAccount:${google_service_account.dataflow.email}"
}


# Cria o repositório de imagens Docker.
resource "google_artifact_registry_repository" "pipelines" {
  project = var.project_id

  location = var.region

  repository_id = "alfabetizacao-pipelines"

  description = "Imagens dos pipelines do Tech Challenge"

  format = "DOCKER"

  labels = local.labels

  depends_on = [
    google_project_service.apis
  ]
}


# Cria alerta para mensagens acumuladas no Pub/Sub.
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  project = var.project_id

  display_name = "Alfabetização - backlog Pub/Sub elevado"

  combiner = "OR"

  enabled = true

  conditions {
    display_name = "Mais de 100 mensagens pendentes por 10 minutos"

    condition_threshold {
      filter = join(
        " ",
        [
          "resource.type = \"pubsub_subscription\"",
          "AND resource.labels.subscription_id = \"${var.pubsub_subscription}\"",
          "AND metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\""
        ]
      )

      comparison = "COMPARISON_GT"

      threshold_value = 100

      duration = "600s"

      aggregations {
        alignment_period = "60s"

        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  documentation {
    content = "Verifique o job Dataflow e a assinatura Pub/Sub. Consulte docs/RUNBOOK.md."

    mime_type = "text/markdown"
  }

  depends_on = [
    google_project_service.apis,
    google_pubsub_subscription.dataflow
  ]
}


# Cria um orçamento mensal para o projeto.
#
# O recurso somente será criado quando a variável
# billing_account estiver preenchida.
resource "google_billing_budget" "monthly" {
  provider = google-beta

  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account

  display_name = "Tech Challenge Alfabetização - orçamento mensal"

  # Filtra os custos exclusivamente para este projeto.
  budget_filter {
    projects = [
      "projects/${data.google_project.current.number}"
    ]
  }

  # Define o valor máximo esperado para o mês.
  amount {
    specified_amount {
      currency_code = var.budget_currency

      units = tostring(var.monthly_budget_brl)
    }
  }

  # Alerta quando atingir 50% do orçamento.
  threshold_rules {
    threshold_percent = 0.50
    spend_basis       = "CURRENT_SPEND"
  }

  # Alerta quando atingir 80% do orçamento.
  threshold_rules {
    threshold_percent = 0.80
    spend_basis       = "CURRENT_SPEND"
  }

  # Alerta quando atingir 90% do orçamento.
  threshold_rules {
    threshold_percent = 0.90
    spend_basis       = "CURRENT_SPEND"
  }

  # Alerta quando atingir 100% do orçamento.
  threshold_rules {
    threshold_percent = 1.00
    spend_basis       = "CURRENT_SPEND"
  }

  # O bloco all_updates_rule não foi incluído.
  # Ele exige um tópico Pub/Sub ou um canal de monitoramento.
  # Os destinatários padrão da conta de faturamento continuam ativos.

  depends_on = [
    google_project_service.apis
  ]
}