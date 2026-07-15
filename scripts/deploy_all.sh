#!/usr/bin/env bash
# Este script automatiza a implantação completa e para na primeira falha.
set -euo pipefail

# Carrega o arquivo .env criado pelo setup.
if [[ -f .env ]]; then
  # Exporta todas as variáveis declaradas.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Desativa a exportação automática.
  set +a
fi

# Inicializa os providers do Terraform.
terraform -chdir=terraform init
# Cria a infraestrutura declarada em terraform/.
terraform -chdir=terraform apply -auto-approve
# Executa a Bronze com a estratégia econômica de amostra física.
python scripts/transferir_dados_inep.py \
  --project-id "$GCP_PROJECT_ID" \
  --bucket "$GCS_BUCKET" \
  --nao-criar-recursos
# Materializa as camadas Silver e Gold.
bash scripts/run_dataform.sh
# Inicia o streaming somente após a parte batch estar pronta.
bash scripts/run_dataflow.sh
