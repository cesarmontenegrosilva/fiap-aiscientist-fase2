"""Executa a carga Bronze dos dados públicos de alfabetização.

Uso mais simples no VS Code/PowerShell:

    python scripts/transferir_dados_inep.py --project-id SEU_PROJECT_ID --sem-parquet

A tabela pública de alunos não é copiada por completo. O código cria uma tabela
física local chamada ``alunos_amostra`` com até 500 linhas e a reutiliza nas
próximas execuções. A recriação só acontece quando ``--recriar-amostra`` é usado.
"""

# Permite anotações de tipo modernas no Python 3.10+.
from __future__ import annotations

# argparse lê parâmetros informados no terminal.
import argparse
# os permite definir as variáveis consumidas pelo restante do projeto.
import os
# sys permite incluir a raiz do repositório no caminho de importação.
import sys
# Path encontra a raiz do repositório de forma independente do sistema operacional.
from pathlib import Path

# Forbidden é usado para explicar conflito de nome ou falta de permissão no bucket.
from google.api_core.exceptions import Forbidden, NotFound
# bigquery é o cliente oficial para datasets, tabelas e consultas.
from google.cloud import bigquery
# storage é o cliente oficial do Cloud Storage.
from google.cloud import storage

# Localiza a pasta principal, que é o diretório acima de scripts/.
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
# Inclui a raiz no sys.path quando o script é chamado diretamente.
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

# Importa a função principal de ingestão depois de ajustar o caminho.
from src.batch.ingest_basedosdados import run  # noqa: E402

# Lista os nomes aceitos pelo parâmetro --tables.
DEFAULT_TABLES = [
    "uf",
    "municipio",
    "alunos_amostra",
    "meta_alfabetizacao_brasil",
    "meta_alfabetizacao_uf",
    "meta_alfabetizacao_municipio",
    "dicionario",
    "diretorio_municipio",
]


def ensure_dataset(
    client: bigquery.Client,
    project_id: str,
    dataset_id: str,
    location: str,
) -> None:
    """Cria um dataset BigQuery somente quando ele ainda não existe."""
    # Monta o nome completo no formato projeto.dataset.
    full_id = f"{project_id}.{dataset_id}"
    # Tenta localizar o dataset.
    try:
        client.get_dataset(full_id)
        # Informa que nenhum recurso novo precisou ser criado.
        print(f"[OK] Dataset existente: {full_id}")
    # NotFound significa que o dataset precisa ser criado.
    except NotFound:
        # Cria a definição do dataset.
        dataset = bigquery.Dataset(full_id)
        # Usa US para ser compatível com a origem pública utilizada no projeto.
        dataset.location = location
        # Adiciona uma descrição simples para identificação no console.
        dataset.description = (
            "Tech Challenge de alfabetização - recurso criado pelo script"
        )
        # Envia a criação ao BigQuery.
        client.create_dataset(dataset)
        # Confirma a criação no terminal.
        print(f"[CRIADO] Dataset: {full_id} ({location})")


def ensure_bucket(
    client: storage.Client,
    project_id: str,
    bucket_name: str,
    location: str,
) -> None:
    """Cria o bucket GCS somente quando a exportação Parquet estiver ativa."""
    # Prepara um objeto de bucket com o nome informado.
    bucket = client.bucket(bucket_name)
    # Tenta ler um bucket já existente.
    try:
        client.get_bucket(bucket_name)
        # Informa que o bucket será reutilizado.
        print(f"[OK] Bucket existente: gs://{bucket_name}")
    # Se não existir, o bucket será criado no projeto do aluno.
    except NotFound:
        # Define a localização compatível com o BigQuery.
        bucket.location = location
        # Ativa controle uniforme de acesso, mais simples para o projeto acadêmico.
        bucket.iam_configuration.uniform_bucket_level_access_enabled = True
        # Cria o bucket.
        client.create_bucket(bucket, project=project_id)
        # Confirma a criação.
        print(f"[CRIADO] Bucket: gs://{bucket_name} ({location})")
    # Forbidden também ocorre quando o nome global do bucket pertence a outra pessoa.
    except Forbidden as exc:
        # Converte o erro técnico em uma orientação compreensível.
        raise RuntimeError(
            f"O nome gs://{bucket_name} já pode pertencer a outro projeto. "
            "Escolha um nome globalmente único."
        ) from exc


def validate_source_access(client: bigquery.Client, location: str) -> None:
    """Valida autenticação e acesso à fonte pública antes da carga principal."""
    # A tabela UF é pequena e serve como teste simples de leitura.
    sql = """
    SELECT 1 AS acesso_ok
    FROM `basedosdados.br_inep_avaliacao_alfabetizacao.uf`
    LIMIT 1
    """
    # Executa e consome o resultado para garantir que o job terminou.
    list(client.query(sql, location=location).result())
    # Mostra uma confirmação amigável.
    print("[OK] Acesso à Base dos Dados confirmado.")


def configure_environment(args: argparse.Namespace) -> None:
    """Converte argumentos do terminal em variáveis lidas pelo pacote principal."""
    # Organiza os valores em um único dicionário.
    values = {
        "GCP_PROJECT_ID": args.project_id,
        "GCP_REGION": args.region,
        "BIGQUERY_LOCATION": args.location,
        "GCS_BUCKET": args.bucket,
        "BQ_DATASET_BRONZE": args.bronze_dataset,
        "BQ_DATASET_SILVER": args.silver_dataset,
        "BQ_DATASET_GOLD": args.gold_dataset,
        "BQ_DATASET_MONITORING": args.monitoring_dataset,
        "SOURCE_PROJECT": "basedosdados",
        "SOURCE_DATASET": "br_inep_avaliacao_alfabetizacao",
        "MAXIMUM_BYTES_BILLED": str(args.maximum_bytes_billed),
    }
    # Publica cada valor no ambiente do processo Python atual.
    for key, value in values.items():
        os.environ[key] = str(value)


def parse_args() -> argparse.Namespace:
    """Define e valida os parâmetros aceitos pelo script."""
    # Cria o parser com uma descrição exibida em --help.
    parser = argparse.ArgumentParser(
        description=(
            "Transfere dados públicos do INEP/Base dos Dados para o BigQuery Bronze."
        )
    )
    # O projeto pode vir do terminal ou da variável GCP_PROJECT_ID.
    parser.add_argument(
        "--project-id",
        default=os.getenv("GCP_PROJECT_ID"),
        required=not bool(os.getenv("GCP_PROJECT_ID")),
        help="ID do seu projeto GCP, que executará e faturará as consultas.",
    )
    # O bucket é opcional quando --sem-parquet é utilizado.
    parser.add_argument(
        "--bucket",
        default=None,
        help="Bucket GCS. Padrão: <project-id>-alfabetizacao-lake.",
    )
    # Região padrão dos serviços regionais.
    parser.add_argument("--region", default="us-central1")
    # Localização multirregional do BigQuery e do bucket.
    parser.add_argument(
        "--location",
        default="US",
        help="Localização BigQuery/GCS. Mantenha US para compatibilidade.",
    )
    # Permite trocar o nome do dataset Bronze.
    parser.add_argument("--bronze-dataset", default="alfabetizacao_bronze")
    # Permite trocar o nome do dataset Silver.
    parser.add_argument("--silver-dataset", default="alfabetizacao_silver")
    # Permite trocar o nome do dataset Gold.
    parser.add_argument("--gold-dataset", default="alfabetizacao_gold")
    # Permite trocar o nome do dataset de monitoramento.
    parser.add_argument(
        "--monitoring-dataset",
        default="alfabetizacao_monitoring",
    )
    # Permite executar somente parte das fontes configuradas.
    parser.add_argument(
        "--tables",
        nargs="+",
        choices=DEFAULT_TABLES,
        default=DEFAULT_TABLES,
        help="Fontes que serão copiadas. Por padrão, todas.",
    )
    # Desabilita a exportação para o Cloud Storage em testes iniciais.
    parser.add_argument(
        "--sem-parquet",
        action="store_true",
        help="Copia somente para BigQuery, sem snapshot Parquet no GCS.",
    )
    # Evita criação automática quando a infraestrutura veio do Terraform.
    parser.add_argument(
        "--nao-criar-recursos",
        action="store_true",
        help="Exige que datasets e bucket já existam.",
    )
    # Recria conscientemente a amostra, gerando nova leitura da tabela pública.
    parser.add_argument(
        "--recriar-amostra",
        action="store_true",
        help="Apaga e recria alunos_amostra; use somente quando necessário.",
    )
    # Define um teto por consulta para evitar uma cobrança inesperada.
    parser.add_argument(
        "--maximum-bytes-billed",
        type=int,
        default=10 * 1024**3,
        help="Teto por consulta em bytes; padrão de 10 GiB.",
    )
    # Converte os valores informados em um Namespace.
    args = parser.parse_args()
    # Gera um nome padrão para o bucket quando o usuário não informou outro.
    if args.bucket is None:
        args.bucket = f"{args.project_id}-alfabetizacao-lake"
    # Devolve os parâmetros já normalizados.
    return args


def main() -> None:
    """Coordena validação, criação de recursos mínimos e ingestão."""
    # Lê os argumentos do terminal.
    args = parse_args()
    # Publica os argumentos como variáveis de ambiente para Settings.from_env().
    configure_environment(args)
    # Cria o cliente BigQuery usando o projeto do aluno.
    bq_client = bigquery.Client(
        project=args.project_id,
        location=args.location,
    )
    # Verifica a autenticação e a fonte pública antes de criar tabelas.
    validate_source_access(bq_client, args.location)
    # Cria recursos mínimos somente quando o usuário não desabilitou essa opção.
    if not args.nao_criar_recursos:
        # Cria ou reutiliza o dataset Bronze.
        ensure_dataset(
            bq_client,
            args.project_id,
            args.bronze_dataset,
            args.location,
        )
        # Cria ou reutiliza o dataset de auditoria.
        ensure_dataset(
            bq_client,
            args.project_id,
            args.monitoring_dataset,
            args.location,
        )
        # O bucket só é necessário quando a opção Parquet está ativa.
        if not args.sem_parquet:
            # Cria o cliente do Cloud Storage.
            gcs_client = storage.Client(project=args.project_id)
            # Cria ou reutiliza o bucket.
            ensure_bucket(
                gcs_client,
                args.project_id,
                args.bucket,
                args.location,
            )
    # Resume as escolhas antes de iniciar a transferência.
    print("\nIniciando transferência:")
    # Mostra a fonte pública principal.
    print("  Origem: basedosdados.br_inep_avaliacao_alfabetizacao")
    # Mostra o destino da camada Bronze.
    print(f"  Destino BigQuery: {args.project_id}.{args.bronze_dataset}")
    # Mostra a regra econômica aplicada à tabela grande.
    print("  Alunos: tabela física alunos_amostra, criada somente uma vez")
    # Mostra o bucket quando a exportação estiver ativa.
    if not args.sem_parquet:
        print(f"  Destino GCS: gs://{args.bucket}/bronze/batch/")
    # Mostra as fontes selecionadas.
    print(f"  Tabelas: {', '.join(args.tables)}\n")
    # Executa a ingestão configurada no YAML.
    run(
        config_path=str(REPOSITORY_ROOT / "config" / "sources.yaml"),
        export_parquet=not args.sem_parquet,
        only=set(args.tables),
        force_refresh_sample=args.recriar_amostra,
    )
    # Informa o término no terminal.
    print("\n[CONCLUÍDO] Dados transferidos para a camada Bronze.")
    # Reforça que a amostra não será recriada em uma execução comum.
    print("[FINOPS] alunos_amostra será reutilizada nas próximas execuções.")
    # Mostra onde consultar a auditoria.
    print(
        "Consulte a auditoria em "
        f"`{args.project_id}.{args.monitoring_dataset}.pipeline_runs`."
    )


# Executa main somente quando o usuário chama este arquivo diretamente.
if __name__ == "__main__":
    main()
