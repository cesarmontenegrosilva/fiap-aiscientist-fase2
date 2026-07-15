#!/usr/bin/env bash
# Interrompe o script em caso de erro ou variável não definida.
set -euo pipefail

# Carrega o arquivo .env quando ele existir.
if [[ -f .env ]]; then
  # Exporta as variáveis do arquivo.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Desativa a exportação automática.
  set +a
fi

# Define a região padrão do Dataflow.
: "${GCP_REGION:=us-central1}"
# Usa o projeto definido no .env ou na configuração atual do gcloud.
PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
# Exige um projeto válido para evitar cancelar jobs no lugar errado.
: "${PROJECT_ID:?Defina GCP_PROJECT_ID ou execute gcloud config set project}"

# Lista apenas jobs ativos cujo nome começa com alfabetizacao-stream.
JOBS="$(gcloud dataflow jobs list \
  --project "$PROJECT_ID" \
  --region "$GCP_REGION" \
  --status=active \
  --filter='name~alfabetizacao-stream' \
  --format='value(id)')"

# Encerra normalmente quando não há streaming ativo.
if [[ -z "$JOBS" ]]; then
  echo "Nenhum job Dataflow ativo encontrado."
  exit 0
fi

# Percorre os IDs encontrados, um por linha.
while read -r job; do
  # Ignora linhas vazias.
  [[ -z "$job" ]] && continue
  # Cancela o job para interromper o consumo de recursos.
  gcloud dataflow jobs cancel "$job" \
    --project "$PROJECT_ID" \
    --region "$GCP_REGION" \
    --quiet
done <<< "$JOBS"

# Confirma a solicitação de cancelamento.
echo "Todos os jobs de streaming do projeto foram cancelados."
