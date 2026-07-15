#!/usr/bin/env bash
# Interrompe a rotina se qualquer etapa falhar.
set -euo pipefail

# Carrega as variáveis do arquivo .env quando ele existir.
if [[ -f .env ]]; then
  # Exporta automaticamente as variáveis lidas do arquivo.
  set -a
  # shellcheck disable=SC1091
  source .env
  # Desativa a exportação automática após a leitura.
  set +a
fi

# Informa a primeira etapa ao usuário.
echo "[1/3] Ingestão batch da Base dos Dados"
# Executa a ingestão; alunos_amostra será criada uma vez e reutilizada.
python scripts/transferir_dados_inep.py --project-id "$GCP_PROJECT_ID" --sem-parquet

# Informa a segunda etapa ao usuário.
echo "[2/3] Transformações Dataform Silver e Gold"
# Executa o script que compila e materializa o Dataform.
bash scripts/run_dataform.sh

# Informa a terceira etapa ao usuário.
echo "[3/3] Verificações operacionais de qualidade"
# Executa as consultas Python adicionais de qualidade.
python -m src.quality.run_checks

# Confirma que todas as etapas terminaram sem erro.
echo "Pipeline batch concluída com sucesso."
