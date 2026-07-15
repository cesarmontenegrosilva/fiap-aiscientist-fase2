#!/usr/bin/env bash
# Interrompe na primeira falha.
set -euo pipefail

# Carrega o arquivo .env quando ele existir.
if [[ -f .env ]]; then
  # Exporta os valores lidos.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Desativa a exportação automática.
  set +a
fi

# Exige o ID do projeto.
: "${GCP_PROJECT_ID:?Carregue o arquivo .env}"
# Define a região padrão.
: "${GCP_REGION:=us-central1}"
# Exige o bucket do projeto.
: "${GCS_BUCKET:?Defina GCS_BUCKET}"

# Monta o endereço da imagem no Artifact Registry.
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/alfabetizacao-pipelines/pipeline:latest"
# Monta o e-mail da conta de serviço do job batch.
BATCH_SA="alfabetizacao-batch@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Constrói a imagem Docker e envia ao Artifact Registry.
gcloud builds submit \
  --project "$GCP_PROJECT_ID" \
  --tag "$IMAGE" \
  .

# Cria ou atualiza o Cloud Run Job responsável pelo batch.
gcloud run jobs deploy alfabetizacao-batch \
  --project "$GCP_PROJECT_ID" \
  --region "$GCP_REGION" \
  --image "$IMAGE" \
  --service-account "$BATCH_SA" \
  --set-env-vars="GCP_PROJECT_ID=${GCP_PROJECT_ID},GCP_REGION=${GCP_REGION},BIGQUERY_LOCATION=US,GCS_BUCKET=${GCS_BUCKET},BQ_DATASET_BRONZE=alfabetizacao_bronze,BQ_DATASET_MONITORING=alfabetizacao_monitoring,MAXIMUM_BYTES_BILLED=10737418240" \
  --max-retries 1 \
  --task-timeout 3600s \
  --memory 1Gi \
  --cpu 1

# Executa o job uma vez e aguarda o resultado.
gcloud run jobs execute alfabetizacao-batch \
  --project "$GCP_PROJECT_ID" \
  --region "$GCP_REGION" \
  --wait
