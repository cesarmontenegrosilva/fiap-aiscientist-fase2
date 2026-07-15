#!/usr/bin/env bash
# Interrompe a verificação quando uma etapa obrigatória falhar.
set -euo pipefail

# Carrega as variáveis do projeto quando o .env existir.
if [[ -f .env ]]; then
  # Exporta os valores do arquivo.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Encerra a exportação automática.
  set +a
fi

# Exige o ID do projeto para montar as consultas.
: "${GCP_PROJECT_ID:?Carregue o arquivo .env}"

# Publica cinco eventos de teste no Pub/Sub.
python -m src.streaming.publisher --count 5 --interval 0.2
# Aguarda alguns segundos para o Dataflow processar os eventos.
sleep 20
# Conta quantos eventos válidos chegaram à Bronze.
bq query --project_id="$GCP_PROJECT_ID" --use_legacy_sql=false \
  "SELECT COUNT(*) AS eventos FROM \`${GCP_PROJECT_ID}.alfabetizacao_bronze.eventos_indicador\`"
# Mostra os dez primeiros municípios do ranking Gold.
bq query --project_id="$GCP_PROJECT_ID" --use_legacy_sql=false \
  "SELECT * FROM \`${GCP_PROJECT_ID}.alfabetizacao_gold.ranking_municipios\` ORDER BY ranking_brasil LIMIT 10"
# Executa as verificações Python de qualidade e volume.
python -m src.quality.run_checks
