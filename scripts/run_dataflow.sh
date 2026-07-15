#!/usr/bin/env bash
# Interrompe ao primeiro erro e impede o uso silencioso de variável não definida.
set -euo pipefail

# Carrega o arquivo .env quando a execução parte da raiz do repositório.
if [[ -f .env ]]; then
  # Exporta todas as variáveis lidas.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Volta ao comportamento padrão do shell.
  set +a
fi

# Exige o ID do projeto GCP.
: "${GCP_PROJECT_ID:?Defina GCP_PROJECT_ID no .env}"
# Usa us-central1 quando nenhuma região foi definida.
: "${GCP_REGION:=us-central1}"
# Exige o bucket usado para arquivos temporários do Dataflow.
: "${GCS_BUCKET:?Defina GCS_BUCKET no .env}"
# Usa o nome padrão da assinatura Pub/Sub.
: "${PUBSUB_SUBSCRIPTION:=alfabetizacao-indicadores-dataflow}"
# Usa o nome padrão do dataset Bronze.
: "${BQ_DATASET_BRONZE:=alfabetizacao_bronze}"

# Define a conta de serviço dos workers, permitindo sobrescrever pelo .env.
DATAFLOW_SA="${DATAFLOW_SERVICE_ACCOUNT:-alfabetizacao-dataflow@${GCP_PROJECT_ID}.iam.gserviceaccount.com}"
# Cria um nome único para o job usando data e hora.
JOB_NAME="alfabetizacao-stream-$(date +%Y%m%d-%H%M%S)"

# Inicia o pipeline Apache Beam no serviço gerenciado Dataflow.
python -m src.streaming.pipeline \
  --runner DataflowRunner \
  --project "$GCP_PROJECT_ID" \
  --region "$GCP_REGION" \
  --temp_location "gs://${GCS_BUCKET}/tmp" \
  --staging_location "gs://${GCS_BUCKET}/staging" \
  --service_account_email "$DATAFLOW_SA" \
  --job_name "$JOB_NAME" \
  --streaming \
  --enable_streaming_engine \
  --autoscaling_algorithm THROUGHPUT_BASED \
  --max_num_workers 2 \
  --machine_type n1-standard-1 \
  --requirements_file requirements-dataflow.txt \
  --setup_file ./setup.py \
  --input_subscription "projects/${GCP_PROJECT_ID}/subscriptions/${PUBSUB_SUBSCRIPTION}" \
  --output_table "${GCP_PROJECT_ID}:${BQ_DATASET_BRONZE}.eventos_indicador" \
  --rejected_table "${GCP_PROJECT_ID}:${BQ_DATASET_BRONZE}.eventos_rejeitados"
