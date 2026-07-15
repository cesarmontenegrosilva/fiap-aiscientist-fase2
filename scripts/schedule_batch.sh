#!/usr/bin/env bash
# Interrompe na primeira falha.
set -euo pipefail

# Carrega as variáveis locais.
if [[ -f .env ]]; then
  # Exporta as variáveis lidas do arquivo.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Encerra a exportação automática.
  set +a
fi

# Exige o ID do projeto.
: "${GCP_PROJECT_ID:?Carregue o arquivo .env}"
# Usa us-central1 por padrão.
: "${GCP_REGION:=us-central1}"
# Usa a conta batch para invocar o job.
CALLER_SA="alfabetizacao-batch@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
# Monta a URL da API do Cloud Run Job.
URI="https://${GCP_REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${GCP_PROJECT_ID}/jobs/alfabetizacao-batch:run"

# Concede permissão para a conta de serviço invocar o job.
gcloud run jobs add-iam-policy-binding alfabetizacao-batch \
  --project "$GCP_PROJECT_ID" \
  --region "$GCP_REGION" \
  --member="serviceAccount:${CALLER_SA}" \
  --role="roles/run.invoker"

# Tenta criar o agendamento semanal às segundas-feiras, 06:00 de Recife.
gcloud scheduler jobs create http alfabetizacao-batch-semanal \
  --project "$GCP_PROJECT_ID" \
  --location "$GCP_REGION" \
  --schedule "0 6 * * 1" \
  --time-zone "America/Recife" \
  --uri "$URI" \
  --http-method POST \
  --oauth-service-account-email "$CALLER_SA" \
  --oauth-token-scope "https://www.googleapis.com/auth/cloud-platform" \
  || \
# Se o agendamento já existir, atualiza os mesmos parâmetros.
gcloud scheduler jobs update http alfabetizacao-batch-semanal \
  --project "$GCP_PROJECT_ID" \
  --location "$GCP_REGION" \
  --schedule "0 6 * * 1" \
  --time-zone "America/Recife" \
  --uri "$URI" \
  --http-method POST \
  --oauth-service-account-email "$CALLER_SA" \
  --oauth-token-scope "https://www.googleapis.com/auth/cloud-platform"
