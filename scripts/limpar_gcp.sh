#!/usr/bin/env bash
# Interrompe ao primeiro erro, em variável ausente e em falha dentro de pipe.
set -Eeuo pipefail

# Exibe a ajuda do script.
usage() {
  # Usa um bloco literal para manter a formatação.
  cat <<'EOF'
Uso:
  bash scripts/limpar_gcp.sh --project-id PROJETO --bucket BUCKET [opções]

Opções:
  --region REGIAO       Região dos recursos; padrão us-central1
  --dry-run             Apenas mostra os comandos
  --yes                 Não solicita confirmação interativa
  --skip-terraform      Não executa terraform destroy
  --disable-apis        Desativa as APIs ao final
  --unlink-billing      Desvincula a conta de faturamento
  --delete-project      Exclui também o projeto GCP inteiro
  -h, --help            Mostra esta ajuda

Exemplo seguro:
  bash scripts/limpar_gcp.sh \
    --project-id meu-projeto \
    --bucket meu-projeto-alfabetizacao-lake \
    --delete-project \
    --dry-run
EOF
}

# Inicia o ID do projeto vazio para obrigar seu preenchimento.
PROJECT_ID=""
# Define a região padrão dos recursos regionais.
REGION="us-central1"
# Inicia o nome do bucket vazio.
BUCKET=""
# Define o modo de simulação como desligado.
DRY_RUN=false
# Define a confirmação automática como desligada.
ASSUME_YES=false
# Define o uso do Terraform como ativo.
SKIP_TERRAFORM=false
# Define a desativação das APIs como opcional.
DISABLE_APIS=false
# Define a desvinculação do billing como opcional.
UNLINK_BILLING=false
# Define a exclusão do projeto como opcional.
DELETE_PROJECT=false

# Processa todos os argumentos recebidos.
while [[ $# -gt 0 ]]; do
  # Analisa o argumento atual.
  case "$1" in
    # Lê o ID do projeto e avança duas posições.
    --project-id) PROJECT_ID="${2:?Informe o project id}"; shift 2 ;;
    # Lê a região e avança duas posições.
    --region) REGION="${2:?Informe a região}"; shift 2 ;;
    # Lê o bucket e avança duas posições.
    --bucket) BUCKET="${2:?Informe o bucket}"; shift 2 ;;
    # Ativa o modo de simulação.
    --dry-run) DRY_RUN=true; shift ;;
    # Pula a confirmação interativa.
    --yes) ASSUME_YES=true; shift ;;
    # Pula terraform destroy.
    --skip-terraform) SKIP_TERRAFORM=true; shift ;;
    # Desativa APIs no final.
    --disable-apis) DISABLE_APIS=true; shift ;;
    # Desvincula a conta de faturamento.
    --unlink-billing) UNLINK_BILLING=true; shift ;;
    # Exclui o projeto inteiro.
    --delete-project) DELETE_PROJECT=true; shift ;;
    # Mostra ajuda e termina sem erro.
    -h|--help) usage; exit 0 ;;
    # Rejeita qualquer opção não reconhecida.
    *) echo "Opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

# Exige o argumento obrigatório --project-id.
[[ -n "$PROJECT_ID" ]] || {
  echo "--project-id é obrigatório" >&2
  exit 2
}
# Bloqueia explicitamente a origem pública.
[[ "$PROJECT_ID" != "basedosdados" ]] || {
  echo "Projeto público basedosdados bloqueado." >&2
  exit 2
}

# Confirma que gcloud e bq estão instalados.
for command_name in gcloud bq; do
  # command -v verifica o PATH sem executar a ferramenta.
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Comando '$command_name' não encontrado." >&2
    exit 1
  }
done

# Localiza a raiz do repositório.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Localiza a pasta Terraform.
TERRAFORM_DIR="$REPO_ROOT/terraform"

# Executa ou apenas mostra um comando.
run() {
  # Imprime o sinal usado para identificar comandos.
  printf '+ '
  # Imprime cada argumento de forma escapada.
  printf '%q ' "$@"
  # Finaliza a linha impressa.
  printf '\n'
  # Executa somente quando DryRun está desligado.
  $DRY_RUN || "$@"
}

# Executa um comando tolerando recurso inexistente.
run_ignore() {
  # Desativa temporariamente a interrupção por erro.
  set +e
  # Executa o comando pela função principal.
  run "$@"
  # Restaura a interrupção por erro.
  set -e
  # Sempre devolve sucesso para continuar a limpeza idempotente.
  return 0
}

# Imprime um separador de etapa.
section() {
  # Imprime linhas e o título recebido.
  printf '\n%s\n%s\n%s\n' \
    "==============================================================================" \
    "$1" \
    "=============================================================================="
}

# Resume o alvo antes de qualquer exclusão.
printf 'Projeto alvo: %s\nRegião: %s\nBucket: %s\nExcluir projeto: %s\nDry run: %s\n' \
  "$PROJECT_ID" \
  "$REGION" \
  "${BUCKET:-<não informado>}" \
  "$DELETE_PROJECT" \
  "$DRY_RUN"

# Solicita confirmação em execuções destrutivas.
if ! $DRY_RUN && ! $ASSUME_YES; then
  # Define uma frase mais forte quando o projeto será excluído.
  if $DELETE_PROJECT; then
    expected="EXCLUIR PROJETO $PROJECT_ID"
  else
    expected="APAGAR RECURSOS $PROJECT_ID"
  fi
  # Mostra um aviso claro.
  echo "ATENÇÃO: esta operação é destrutiva."
  # Lê a frase digitada.
  read -r -p "Digite exatamente '$expected' para continuar: " confirmation
  # Interrompe quando a frase não coincide.
  [[ "$confirmation" == "$expected" ]] || {
    echo "Confirmação incorreta. Nenhum recurso foi removido." >&2
    exit 1
  }
fi

# Mostra a primeira etapa.
section "1/9 - Removendo agendamentos do Cloud Scheduler"
# Lista agendamentos relacionados ao projeto.
mapfile -t scheduler_jobs < <(
  gcloud scheduler jobs list \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --filter="name~alfabetizacao" \
    --format='value(name)' 2>/dev/null || true
)
# Percorre os agendamentos encontrados.
for full_name in "${scheduler_jobs[@]:-}"; do
  # Ignora entradas vazias.
  [[ -n "$full_name" ]] || continue
  # Exclui o agendamento pelo nome curto.
  run_ignore gcloud scheduler jobs delete "${full_name##*/}" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --quiet
done

# Mostra a segunda etapa.
section "2/9 - Cancelando jobs ativos do Dataflow"
# Lista jobs ativos cujo nome contém alfabetizacao.
mapfile -t dataflow_jobs < <(
  gcloud dataflow jobs list \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --status=active \
    --filter="name~alfabetizacao" \
    --format='value(id)' 2>/dev/null || true
)
# Percorre cada job encontrado.
for job_id in "${dataflow_jobs[@]:-}"; do
  # Ignora IDs vazios.
  [[ -n "$job_id" ]] || continue
  # Cancela o job para parar os workers.
  run_ignore gcloud dataflow jobs cancel "$job_id" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --quiet
done

# Mostra a terceira etapa.
section "3/9 - Cancelando e removendo Cloud Run"
# Lista execuções do job batch.
mapfile -t executions < <(
  gcloud run jobs executions list \
    --job=alfabetizacao-batch \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format='value(metadata.name)' 2>/dev/null || true
)
# Percorre execuções visíveis.
for execution in "${executions[@]:-}"; do
  # Ignora entradas vazias.
  [[ -n "$execution" ]] || continue
  # Solicita cancelamento; execuções finalizadas são toleradas.
  run_ignore gcloud run jobs executions cancel "$execution" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --quiet
done
# Exclui o job batch.
run_ignore gcloud run jobs delete alfabetizacao-batch \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --quiet

# Mostra a quarta etapa.
section "4/9 - Executando terraform destroy quando houver state local"
# Usa Terraform somente quando permitido, instalado, com state e bucket informado.
if ! $SKIP_TERRAFORM \
  && [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]] \
  && command -v terraform >/dev/null 2>&1 \
  && [[ -n "$BUCKET" ]]; then
  # Destrói os recursos controlados pelo state.
  run_ignore terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION" \
    -var="bigquery_location=US" \
    -var="bucket_name=$BUCKET" \
    -var="allow_destroy_data=true"
else
  # Explica por que a limpeza manual será usada.
  echo "Terraform não utilizado; seguindo com comandos idempotentes."
fi

# Mostra a quinta etapa.
section "5/9 - Removendo Pub/Sub"
# Exclui a assinatura antes do tópico.
run_ignore gcloud pubsub subscriptions delete alfabetizacao-indicadores-dataflow \
  --project="$PROJECT_ID" \
  --quiet
# Exclui o tópico.
run_ignore gcloud pubsub topics delete alfabetizacao-indicadores \
  --project="$PROJECT_ID" \
  --quiet

# Mostra a sexta etapa.
section "6/9 - Removendo datasets BigQuery"
# Percorre os datasets da arquitetura.
for dataset in \
  alfabetizacao_bronze \
  alfabetizacao_silver \
  alfabetizacao_gold \
  alfabetizacao_monitoring \
  alfabetizacao_assertions; do
  # Remove recursivamente tabelas e dataset.
  run_ignore bq rm \
    --recursive=true \
    --force=true \
    --dataset=true \
    "$PROJECT_ID:$dataset"
done

# Mostra a sétima etapa.
section "7/9 - Removendo objetos, versões e bucket do Cloud Storage"
# Executa somente quando o bucket foi informado.
if [[ -n "$BUCKET" ]]; then
  # Remove objetos e versões anteriores.
  run_ignore gcloud storage rm \
    --recursive \
    --all-versions \
    "gs://$BUCKET/**"
  # Remove o bucket vazio.
  run_ignore gcloud storage buckets delete "gs://$BUCKET" --quiet
else
  # Avisa que o bucket foi preservado por falta do nome explícito.
  echo "Bucket não informado; use --bucket NOME_DO_BUCKET."
fi

# Mostra a oitava etapa.
section "8/9 - Removendo Artifact Registry e contas de serviço"
# Exclui o repositório de imagens.
run_ignore gcloud artifacts repositories delete alfabetizacao-pipelines \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --quiet
# Percorre as contas criadas pelo projeto.
for account in alfabetizacao-batch alfabetizacao-dataflow; do
  # Exclui cada conta de serviço.
  run_ignore gcloud iam service-accounts delete \
    "$account@$PROJECT_ID.iam.gserviceaccount.com" \
    --project="$PROJECT_ID" \
    --quiet
done

# Mostra a nona etapa.
section "9/9 - Finalizando APIs, billing e projeto"
# Desativa APIs somente quando solicitado.
if $DISABLE_APIS; then
  # Desativa os serviços usados pela aplicação.
  run_ignore gcloud services disable \
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
    --project="$PROJECT_ID" \
    --force \
    --quiet
fi
# Desvincula faturamento somente quando solicitado.
if $UNLINK_BILLING; then
  # Remove o vínculo do projeto com a conta de faturamento.
  run_ignore gcloud billing projects unlink "$PROJECT_ID" --quiet
fi
# Exclui o projeto inteiro somente quando solicitado.
if $DELETE_PROJECT; then
  # Marca o projeto temporário para exclusão.
  run gcloud projects delete "$PROJECT_ID" --quiet
fi

# Mostra o resultado apropriado para uma simulação.
if $DRY_RUN; then
  echo "Simulação concluída. Nenhum recurso foi alterado."
# Mostra o resultado quando o projeto foi marcado para exclusão.
elif $DELETE_PROJECT; then
  echo "Projeto marcado para exclusão. Confira com:"
  echo "gcloud projects list --filter='projectId=$PROJECT_ID lifecycleState:DELETE_REQUESTED'"
# Mostra o resultado quando somente os recursos foram removidos.
else
  echo "Recursos removidos; o projeto foi mantido."
fi
