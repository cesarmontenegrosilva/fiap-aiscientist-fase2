#!/usr/bin/env bash
# Interrompe a configuração se qualquer comando falhar.
set -euo pipefail

# Mostra a forma correta de chamar o script quando faltarem argumentos.
if [[ $# -lt 2 ]]; then
  echo "Uso: $0 <PROJECT_ID> <BUCKET_NAME> [BILLING_ACCOUNT]" >&2
  exit 1
fi

# Primeiro argumento: ID globalmente único do projeto GCP.
PROJECT_ID="$1"
# Segundo argumento: nome globalmente único do bucket.
BUCKET_NAME="$2"
# Terceiro argumento opcional: conta de faturamento.
BILLING_ACCOUNT="${3:-}"
# Usa a região informada no ambiente ou us-central1.
REGION="${GCP_REGION:-us-central1}"

# Confirma que o Google Cloud CLI está instalado.
command -v gcloud >/dev/null || {
  echo "Instale o Google Cloud CLI e reabra o terminal." >&2
  exit 1
}
# Confirma que o Terraform está instalado.
command -v terraform >/dev/null || {
  echo "Instale o Terraform e reabra o terminal." >&2
  exit 1
}
# Confirma que o Python está instalado.
command -v python >/dev/null || {
  echo "Instale o Python 3.10, 3.11 ou 3.12." >&2
  exit 1
}

# Abre o navegador para autenticar a conta Google.
gcloud auth login
# Cria credenciais locais usadas pelas bibliotecas Python.
gcloud auth application-default login

# Verifica se o projeto já existe para a conta autenticada.
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  # Cria o projeto temporário quando ele ainda não existe.
  gcloud projects create "$PROJECT_ID" \
    --name="Tech Challenge Alfabetizacao" \
    --set-as-default
else
  # Define como padrão um projeto que já existia.
  gcloud config set project "$PROJECT_ID"
fi

# Vincula a conta de faturamento quando ela foi informada.
if [[ -n "$BILLING_ACCOUNT" ]]; then
  gcloud billing projects link "$PROJECT_ID" \
    --billing-account="$BILLING_ACCOUNT"
else
  # Avisa que serviços faturáveis exigem uma conta vinculada.
  echo "AVISO: nenhuma billing account foi informada. Vincule uma no console GCP."
fi

# Habilita as APIs necessárias para infraestrutura e execução.
gcloud services enable \
  artifactregistry.googleapis.com \
  bigquery.googleapis.com \
  bigquerystorage.googleapis.com \
  billingbudgets.googleapis.com \
  cloudbilling.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudscheduler.googleapis.com \
  compute.googleapis.com \
  dataflow.googleapis.com \
  dataform.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID"

# Cria o arquivo .env consumido pelos scripts Python e Bash.
cat > .env <<ENV
# ID do projeto temporário criado para a demonstração.
GCP_PROJECT_ID=$PROJECT_ID
# Região usada por Dataflow, Cloud Run e Scheduler.
GCP_REGION=$REGION
# Localização multirregional dos datasets BigQuery.
BIGQUERY_LOCATION=US
# Bucket usado para Parquet e arquivos temporários.
GCS_BUCKET=$BUCKET_NAME
# Nomes dos datasets da arquitetura medalhão.
BQ_DATASET_BRONZE=alfabetizacao_bronze
BQ_DATASET_SILVER=alfabetizacao_silver
BQ_DATASET_GOLD=alfabetizacao_gold
BQ_DATASET_MONITORING=alfabetizacao_monitoring
BQ_DATASET_ASSERTIONS=alfabetizacao_assertions
# Recursos do streaming simulado.
PUBSUB_TOPIC=alfabetizacao-indicadores
PUBSUB_SUBSCRIPTION=alfabetizacao-indicadores-dataflow
# Fonte pública do projeto.
SOURCE_PROJECT=basedosdados
SOURCE_DATASET=br_inep_avaliacao_alfabetizacao
# Pastas temporárias do Dataflow.
TEMP_LOCATION=gs://$BUCKET_NAME/tmp
STAGING_LOCATION=gs://$BUCKET_NAME/staging
# Teto de 10 GiB por consulta BigQuery.
MAXIMUM_BYTES_BILLED=10737418240
ENV

# Cria o arquivo de variáveis do Terraform.
cat > terraform/terraform.tfvars <<TFVARS
# ID do projeto GCP temporário.
project_id         = "$PROJECT_ID"
# Região de recursos regionais.
region             = "$REGION"
# Localização BigQuery e GCS.
bigquery_location  = "US"
# Nome globalmente único do bucket.
bucket_name        = "$BUCKET_NAME"
# Conta de faturamento usada para criar o orçamento, quando informada.
billing_account    = "$BILLING_ACCOUNT"
# Orçamento acadêmico mensal em reais.
monthly_budget_brl = 100
# Permite ao terraform destroy apagar tabelas e objetos do bucket.
allow_destroy_data = true
TFVARS

# Atualiza o defaultProject do Dataform.
python scripts/configure_dataform.py --project-id "$PROJECT_ID"

# Mostra as próximas etapas de forma objetiva.
echo "Configuração concluída."
echo "Próximos comandos:"
echo "  python -m venv .venv"
echo "  source .venv/bin/activate"
echo "  pip install -e '.[dev]'"
echo "  terraform -chdir=terraform init"
echo "  terraform -chdir=terraform apply"
