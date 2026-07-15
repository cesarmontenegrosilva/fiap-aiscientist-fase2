#!/usr/bin/env bash
# Interrompe em caso de erro ou variável ausente.
set -Eeuo pipefail

# Mostra a forma recomendada de executar a limpeza com segurança.
cat <<'EOF'
Este arquivo é apenas um atalho para o script completo de limpeza.

Simulação sem apagar nada:
  bash scripts/limpar_gcp.sh \
    --project-id "$GCP_PROJECT_ID" \
    --bucket "$GCS_BUCKET" \
    --dry-run

Excluir recursos e também o projeto temporário:
  bash scripts/limpar_gcp.sh \
    --project-id "$GCP_PROJECT_ID" \
    --bucket "$GCS_BUCKET" \
    --delete-project
EOF

# Executa o atalho somente quando o usuário informa --execute.
if [[ "${1:-}" == "--execute" ]]; then
  # Exige o ID do projeto.
  : "${GCP_PROJECT_ID:?Defina GCP_PROJECT_ID no ambiente ou no .env}"
  # Exige o nome do bucket.
  : "${GCS_BUCKET:?Defina GCS_BUCKET no ambiente ou no .env}"
  # Substitui o processo atual pelo script completo e solicita exclusão do projeto.
  exec bash scripts/limpar_gcp.sh \
    --project-id "$GCP_PROJECT_ID" \
    --bucket "$GCS_BUCKET" \
    --delete-project
fi
