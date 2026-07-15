output "bucket" {
  value = google_storage_bucket.lake.name
}

output "bronze_dataset" {
  value = google_bigquery_dataset.datasets["bronze"].dataset_id
}

output "silver_dataset" {
  value = google_bigquery_dataset.datasets["silver"].dataset_id
}

output "gold_dataset" {
  value = google_bigquery_dataset.datasets["gold"].dataset_id
}

output "monitoring_dataset" {
  value = google_bigquery_dataset.datasets["monitoring"].dataset_id
}

output "assertions_dataset" {
  value = google_bigquery_dataset.datasets["assertions"].dataset_id
}

output "pubsub_topic" {
  value = google_pubsub_topic.indicator.name
}

output "pubsub_subscription" {
  value = google_pubsub_subscription.dataflow.name
}

output "dataflow_service_account" {
  value = google_service_account.dataflow.email
}

output "batch_service_account" {
  value = google_service_account.batch.email
}

output "artifact_registry" {
  value = google_artifact_registry_repository.pipelines.name
}
