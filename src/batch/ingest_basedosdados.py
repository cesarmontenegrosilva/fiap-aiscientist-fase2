"""Ingestão batch das tabelas públicas da Base dos Dados para a camada Bronze.

O arquivo foi comentado de forma didática para facilitar a apresentação do projeto.
A tabela de alunos recebe um tratamento especial: uma amostra física é criada uma
única vez e reutilizada pelas camadas Silver e Gold para reduzir custos.
"""

# Permite usar anotações de tipo modernas sem avaliar tudo imediatamente.
from __future__ import annotations

# Biblioteca padrão usada para ler argumentos quando o módulo é executado diretamente.
import argparse
# Biblioteca padrão usada para registrar mensagens de execução.
import logging
# Biblioteca padrão usada para medir a duração de cada carga.
import time
# Biblioteca padrão usada para gerar um identificador único por execução.
import uuid
# Datas em UTC são usadas nos metadados e na auditoria.
from datetime import datetime, timezone
# Path facilita validar o caminho do arquivo de configuração.
from pathlib import Path

# NotFound permite tratar de forma controlada tabelas ainda inexistentes.
from google.api_core.exceptions import NotFound
# Cliente oficial do Google para consultar e administrar o BigQuery.
from google.cloud import bigquery

# Função comum que cria configurações de job com limite de bytes e labels.
from src.common.bigquery_utils import query_job_config, quote_table
# Settings lê as variáveis do arquivo .env; load_sources lê o YAML das fontes.
from src.common.config import Settings, load_sources
# Função comum que configura logs estruturados.
from src.common.logging_utils import configure_logging

# Cria o logger deste módulo.
LOGGER = logging.getLogger(__name__)


def ensure_monitoring_table(client: bigquery.Client, settings: Settings) -> None:
    """Cria a tabela de auditoria quando ela ainda não existe."""
    # Monta o identificador completo da tabela de monitoramento.
    table_id = f"{settings.project_id}.{settings.monitoring_dataset}.pipeline_runs"
    # Define as colunas que serão usadas para registrar cada tabela processada.
    schema = [
        bigquery.SchemaField("run_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("pipeline", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("status", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("started_at", "TIMESTAMP", mode="REQUIRED"),
        bigquery.SchemaField("finished_at", "TIMESTAMP"),
        bigquery.SchemaField("duration_seconds", "FLOAT"),
        bigquery.SchemaField("source_table", "STRING"),
        bigquery.SchemaField("destination_table", "STRING"),
        bigquery.SchemaField("rows_processed", "INTEGER"),
        bigquery.SchemaField("error_message", "STRING"),
    ]
    # Tenta localizar a tabela antes de criar uma nova.
    try:
        client.get_table(table_id)
    # A criação acontece somente quando a tabela não foi encontrada.
    except NotFound:
        # Cria o objeto de definição da tabela.
        table = bigquery.Table(table_id, schema=schema)
        # Particiona a auditoria pelo dia de início para reduzir leituras futuras.
        table.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field="started_at",
        )
        # Envia a criação para o BigQuery.
        client.create_table(table)


def record_run(client: bigquery.Client, settings: Settings, row: dict) -> None:
    """Insere uma linha de auditoria sem interromper a pipeline em caso de falha."""
    # Monta o identificador da tabela de auditoria.
    table_id = f"{settings.project_id}.{settings.monitoring_dataset}.pipeline_runs"
    # Insere o dicionário recebido como uma linha JSON.
    errors = client.insert_rows_json(table_id, [row])
    # Uma falha de auditoria é registrada como aviso, mas não invalida a carga principal.
    if errors:
        LOGGER.warning("Falha ao registrar auditoria: %s", errors)


def build_source_list(config: dict) -> list[dict]:
    """Combina as fontes principais e externas em uma lista única."""
    # Lê o projeto público padrão definido no YAML.
    source_project = config["source_project"]
    # Lê o dataset público padrão definido no YAML.
    source_dataset = config["source_dataset"]
    # Inicia a lista que será devolvida ao chamador.
    sources: list[dict] = []
    # Percorre as fontes que compartilham projeto e dataset.
    for source in config.get("sources", []):
        # Copia a configuração e acrescenta os valores herdados.
        sources.append(
            {
                **source,
                "source_project": source_project,
                "source_dataset": source_dataset,
            }
        )
    # Acrescenta fontes externas, que já informam projeto e dataset próprios.
    sources.extend(config.get("external_sources", []))
    # Devolve a lista pronta para processamento.
    return sources


def table_exists(client: bigquery.Client, table_id: str) -> bool:
    """Retorna True quando uma tabela já existe no BigQuery."""
    # Tenta ler os metadados da tabela.
    try:
        client.get_table(table_id)
        # A leitura bem-sucedida indica que a tabela existe.
        return True
    # NotFound é o resultado esperado quando a tabela ainda não foi criada.
    except NotFound:
        # Nesse caso a função informa False.
        return False


def create_bronze_table_if_needed(
    client: bigquery.Client,
    settings: Settings,
    source: dict,
) -> None:
    """Cria uma tabela Bronze vazia com o mesmo esquema da fonte pública."""
    # Coloca crases no identificador completo da tabela pública.
    source_ref = quote_table(
        source["source_project"],
        source["source_dataset"],
        source["source_table"],
    )
    # Coloca crases no identificador completo da tabela de destino.
    destination_ref = quote_table(
        settings.project_id,
        settings.bronze_dataset,
        source["destination_table"],
    )
    # CREATE TABLE IF NOT EXISTS evita recriar uma tabela já existente.
    sql = f"""
    CREATE TABLE IF NOT EXISTS {destination_ref}
    PARTITION BY DATE(_ingested_at)
    OPTIONS(
      description='Snapshot bruto preservado da tabela {source_ref}',
      require_partition_filter=false
    ) AS
    SELECT
      source_data.*,
      CURRENT_TIMESTAMP() AS _ingested_at,
      CAST(NULL AS STRING) AS _ingestion_run_id,
      '{source["source_project"]}.{source["source_dataset"]}.{source["source_table"]}' AS _source_table
    FROM {source_ref} AS source_data
    WHERE FALSE
    """
    # Executa o SQL com um limite máximo de bytes cobrados.
    client.query(
        sql,
        job_config=query_job_config(
            settings.maximum_bytes_billed,
            labels={"pipeline": "batch_ingestion", "layer": "bronze"},
        ),
        location=settings.bq_location,
    ).result()


def export_run_to_parquet(
    client: bigquery.Client,
    settings: Settings,
    destination_table: str,
    run_id: str,
) -> None:
    """Exporta apenas as linhas da execução atual para Parquet/Snappy."""
    # Monta o identificador da tabela Bronze a ser exportada.
    destination_ref = quote_table(
        settings.project_id,
        settings.bronze_dataset,
        destination_table,
    )
    # Monta uma pasta versionada por data e run_id no Cloud Storage.
    uri = (
        f"gs://{settings.bucket}/bronze/batch/{destination_table}/"
        f"ingestion_date={datetime.now(timezone.utc).date().isoformat()}/"
        f"run_id={run_id}/part-*.parquet"
    )
    # O filtro por run_id evita exportar snapshots antigos novamente.
    export_sql = f"""
    EXPORT DATA OPTIONS(
      uri='{uri}',
      format='PARQUET',
      compression='SNAPPY',
      overwrite=true
    ) AS
    SELECT *
    FROM {destination_ref}
    WHERE _ingestion_run_id = @run_id
    """
    # Configura o job com labels e limite de bytes.
    export_config = query_job_config(
        settings.maximum_bytes_billed,
        labels={"pipeline": "batch_export", "layer": "bronze"},
    )
    # Define o parâmetro que será usado dentro do SQL.
    export_config.query_parameters = [
        bigquery.ScalarQueryParameter("run_id", "STRING", run_id)
    ]
    # Executa a exportação e aguarda sua conclusão.
    client.query(
        export_sql,
        job_config=export_config,
        location=settings.bq_location,
    ).result()


def ingest_full_snapshot(
    client: bigquery.Client,
    settings: Settings,
    source: dict,
    run_id: str,
    export_parquet: bool,
) -> tuple[int, str]:
    """Acrescenta um snapshot integral de uma tabela pequena na Bronze."""
    # Garante que a tabela de destino exista com o esquema esperado.
    create_bronze_table_if_needed(client, settings, source)
    # Monta a referência SQL da tabela pública.
    source_ref = quote_table(
        source["source_project"],
        source["source_dataset"],
        source["source_table"],
    )
    # Monta a referência SQL da tabela Bronze.
    destination_ref = quote_table(
        settings.project_id,
        settings.bronze_dataset,
        source["destination_table"],
    )
    # Insere todas as linhas e acrescenta metadados técnicos de rastreabilidade.
    insert_sql = f"""
    INSERT INTO {destination_ref}
    SELECT
      source_data.*,
      CURRENT_TIMESTAMP() AS _ingested_at,
      @run_id AS _ingestion_run_id,
      '{source["source_project"]}.{source["source_dataset"]}.{source["source_table"]}' AS _source_table
    FROM {source_ref} AS source_data
    """
    # Aplica labels e limite máximo de cobrança ao job.
    job_config = query_job_config(
        settings.maximum_bytes_billed,
        labels={"pipeline": "batch_ingestion", "layer": "bronze"},
    )
    # Passa o identificador da execução como parâmetro seguro.
    job_config.query_parameters = [
        bigquery.ScalarQueryParameter("run_id", "STRING", run_id)
    ]
    # Envia a consulta ao BigQuery.
    job = client.query(
        insert_sql,
        job_config=job_config,
        location=settings.bq_location,
    )
    # Aguarda o término da inserção.
    job.result()
    # Recupera o número de linhas afetadas pelo INSERT.
    rows = int(job.num_dml_affected_rows or 0)
    # Exporta o snapshot quando essa opção estiver habilitada.
    if export_parquet:
        export_run_to_parquet(
            client,
            settings,
            source["destination_table"],
            run_id,
        )
    # Devolve quantidade e ação para logs e auditoria.
    return rows, "FULL_SNAPSHOT_CREATED"


def create_or_reuse_physical_sample(
    client: bigquery.Client,
    settings: Settings,
    source: dict,
    run_id: str,
    export_parquet: bool,
    force_refresh: bool,
) -> tuple[int, str]:
    """Cria a amostra física uma vez e a reutiliza nas próximas execuções."""
    # Monta o ID sem crases, usado pela API para consultar os metadados.
    destination_id = (
        f"{settings.project_id}.{settings.bronze_dataset}."
        f"{source['destination_table']}"
    )
    # Se a tabela já existe e não foi solicitada recriação, nenhuma leitura pública ocorre.
    if table_exists(client, destination_id) and not force_refresh:
        # Obtém o número atual de linhas sem executar SELECT na tabela.
        rows = int(client.get_table(destination_id).num_rows or 0)
        # Registra que a tabela local foi reutilizada.
        LOGGER.info(
            "Amostra física já existe e será reutilizada: %s (%s linhas)",
            destination_id,
            rows,
        )
        # Retorna sem consultar novamente a tabela pública de alunos.
        return rows, "PHYSICAL_SAMPLE_REUSED"
    # Quando o usuário pede recriação, a tabela anterior é removida primeiro.
    if force_refresh and table_exists(client, destination_id):
        # not_found_ok deixa a operação idempotente.
        client.delete_table(destination_id, not_found_ok=True)
    # Converte o tamanho da amostra para inteiro e aplica um mínimo de uma linha.
    sample_rows = max(1, int(source.get("sample_rows", 500)))
    # Converte o percentual de blocos para float.
    sample_percent = float(source.get("sample_percent", 1))
    # Impede um valor inválido ou maior que 100.
    if not 0 < sample_percent <= 100:
        raise ValueError("sample_percent deve estar entre 0 e 100")
    # Monta a referência SQL da tabela pública de alunos.
    source_ref = quote_table(
        source["source_project"],
        source["source_dataset"],
        source["source_table"],
    )
    # Monta a referência SQL da tabela física local.
    destination_ref = quote_table(
        settings.project_id,
        settings.bronze_dataset,
        source["destination_table"],
    )
    # TABLESAMPLE lê apenas uma porcentagem dos blocos antes de aplicar LIMIT.
    # Isso reduz a leitura inicial quando comparado a um SELECT * LIMIT isolado.
    create_sql = f"""
    CREATE TABLE {destination_ref}
    PARTITION BY DATE(_ingested_at)
    OPTIONS(
      description='Amostra física acadêmica criada uma única vez a partir de {source_ref}'
    ) AS
    SELECT
      source_data.*,
      CURRENT_TIMESTAMP() AS _ingested_at,
      @run_id AS _ingestion_run_id,
      '{source["source_project"]}.{source["source_dataset"]}.{source["source_table"]}' AS _source_table
    FROM {source_ref} AS source_data
    TABLESAMPLE SYSTEM ({sample_percent:g} PERCENT)
    LIMIT {sample_rows}
    """
    # Configura o job com teto de cobrança e labels para rastreabilidade.
    job_config = query_job_config(
        settings.maximum_bytes_billed,
        labels={"pipeline": "physical_sample", "layer": "bronze"},
    )
    # Informa o run_id usado nos metadados da amostra.
    job_config.query_parameters = [
        bigquery.ScalarQueryParameter("run_id", "STRING", run_id)
    ]
    # Cria a tabela física e aguarda a conclusão.
    client.query(
        create_sql,
        job_config=job_config,
        location=settings.bq_location,
    ).result()
    # Lê os metadados da tabela recém-criada para obter a quantidade de linhas.
    rows = int(client.get_table(destination_id).num_rows or 0)
    # Avisa caso a amostragem de blocos tenha retornado menos linhas que o limite desejado.
    if rows < sample_rows:
        LOGGER.warning(
            "A amostra contém %s linhas, abaixo do limite de %s. "
            "Aumente sample_percent em config/sources.yaml somente se necessário.",
            rows,
            sample_rows,
        )
    # Exporta a amostra recém-criada para Parquet quando solicitado.
    if export_parquet:
        export_run_to_parquet(
            client,
            settings,
            source["destination_table"],
            run_id,
        )
    # Retorna a quantidade e informa que a amostra foi criada nesta execução.
    return rows, "PHYSICAL_SAMPLE_CREATED"


def ingest_source(
    client: bigquery.Client,
    settings: Settings,
    source: dict,
    run_id: str,
    export_parquet: bool,
    force_refresh_sample: bool,
) -> tuple[int, str]:
    """Escolhe a estratégia correta conforme o campo mode do YAML."""
    # full_snapshot é usado nas tabelas pequenas.
    if source.get("mode", "full_snapshot") == "full_snapshot":
        return ingest_full_snapshot(
            client,
            settings,
            source,
            run_id,
            export_parquet,
        )
    # physical_sample_once é usado apenas para a tabela grande de alunos.
    if source.get("mode") == "physical_sample_once":
        return create_or_reuse_physical_sample(
            client,
            settings,
            source,
            run_id,
            export_parquet,
            force_refresh_sample,
        )
    # Modos desconhecidos são rejeitados para evitar uma carga acidental.
    raise ValueError(f"Modo de ingestão não suportado: {source.get('mode')}")


def run(
    config_path: str,
    export_parquet: bool = True,
    only: set[str] | None = None,
    force_refresh_sample: bool = False,
) -> None:
    """Executa todas as fontes selecionadas e registra o resultado na auditoria."""
    # Configura a saída dos logs.
    configure_logging()
    # Lê projeto, datasets, bucket e limites a partir das variáveis de ambiente.
    settings = Settings.from_env()
    # Carrega a lista de fontes do arquivo YAML.
    config = load_sources(config_path)
    # Cria o cliente BigQuery no projeto do aluno.
    client = bigquery.Client(
        project=settings.project_id,
        location=settings.bq_location,
    )
    # Garante que a tabela de auditoria esteja pronta.
    ensure_monitoring_table(client, settings)
    # Cria um identificador único para esta execução batch.
    run_id = str(uuid.uuid4())
    # Marca o início global para calcular a duração total.
    global_start = time.monotonic()
    # Registra o início da carga.
    LOGGER.info(
        "Início da ingestão batch",
        extra={"run_id": run_id, "pipeline": "batch_basedosdados"},
    )
    # Guarda nomes de tabelas que apresentarem erro.
    failures: list[str] = []
    # Percorre todas as fontes configuradas.
    for source in build_source_list(config):
        # Ignora fontes fora da seleção feita pelo usuário.
        if only and source["name"] not in only:
            continue
        # Marca o início da tabela atual.
        table_start = time.monotonic()
        # Guarda o horário UTC usado na auditoria.
        table_started_at = datetime.now(timezone.utc)
        # Facilita o uso do nome da tabela de destino nos logs.
        destination = source["destination_table"]
        # Monta o nome completo da origem pública.
        source_table = (
            f"{source['source_project']}."
            f"{source['source_dataset']}."
            f"{source['source_table']}"
        )
        # Tenta processar a fonte atual.
        try:
            # Executa snapshot completo ou amostra física conforme o YAML.
            rows, action = ingest_source(
                client,
                settings,
                source,
                run_id,
                export_parquet=export_parquet,
                force_refresh_sample=force_refresh_sample,
            )
            # Calcula a duração da tabela atual.
            duration = time.monotonic() - table_start
            # Registra a execução bem-sucedida na tabela de monitoramento.
            record_run(
                client,
                settings,
                {
                    "run_id": run_id,
                    "pipeline": "batch_basedosdados",
                    "status": "SUCCESS",
                    "started_at": table_started_at.isoformat(),
                    "finished_at": datetime.now(timezone.utc).isoformat(),
                    "duration_seconds": duration,
                    "source_table": source_table,
                    "destination_table": destination,
                    "rows_processed": rows,
                    "error_message": None,
                },
            )
            # Mostra no log a estratégia aplicada e a quantidade de linhas.
            LOGGER.info(
                "Tabela processada",
                extra={
                    "run_id": run_id,
                    "pipeline": "batch_basedosdados",
                    "table": destination,
                    "rows": rows,
                    "action": action,
                    "duration_seconds": round(duration, 3),
                },
            )
        # Captura qualquer erro para registrar auditoria antes de encerrar.
        except Exception as exc:  # noqa: BLE001
            # Adiciona a tabela à lista de falhas.
            failures.append(destination)
            # Calcula quanto tempo passou até o erro.
            duration = time.monotonic() - table_start
            # Registra os detalhes da falha no BigQuery.
            record_run(
                client,
                settings,
                {
                    "run_id": run_id,
                    "pipeline": "batch_basedosdados",
                    "status": "FAILED",
                    "started_at": table_started_at.isoformat(),
                    "finished_at": datetime.now(timezone.utc).isoformat(),
                    "duration_seconds": duration,
                    "source_table": source_table,
                    "destination_table": destination,
                    "rows_processed": None,
                    "error_message": str(exc)[:5000],
                },
            )
            # Mostra a pilha completa no log para facilitar o diagnóstico.
            LOGGER.exception("Falha na ingestão de %s", destination)
    # Calcula a duração de toda a execução batch.
    total_duration = time.monotonic() - global_start
    # Registra o encerramento geral.
    LOGGER.info(
        "Fim da ingestão batch",
        extra={
            "run_id": run_id,
            "pipeline": "batch_basedosdados",
            "duration_seconds": round(total_duration, 3),
        },
    )
    # Se alguma tabela falhou, devolve um erro final para CI, Cloud Run ou terminal.
    if failures:
        raise RuntimeError(
            f"Falha em {len(failures)} tabela(s): {', '.join(failures)}"
        )


def parse_args() -> argparse.Namespace:
    """Lê argumentos quando este módulo é executado diretamente."""
    # Cria o parser da linha de comando.
    parser = argparse.ArgumentParser(
        description="Ingestão batch da Base dos Dados"
    )
    # Permite trocar o catálogo de fontes.
    parser.add_argument("--config", default="config/sources.yaml")
    # Permite desabilitar a exportação Parquet para um teste mais simples.
    parser.add_argument(
        "--no-export-parquet",
        action="store_true",
        help="Não exportar snapshots para o Cloud Storage",
    )
    # Permite executar apenas algumas fontes pelo nome do YAML.
    parser.add_argument(
        "--only",
        nargs="*",
        help="Executar apenas fontes específicas pelo campo name do YAML",
    )
    # Permite recriar a amostra física conscientemente.
    parser.add_argument(
        "--force-refresh-sample",
        action="store_true",
        help="Apaga e recria alunos_amostra; pode gerar nova leitura e custo",
    )
    # Devolve o objeto com os valores informados.
    return parser.parse_args()


# Este bloco só roda quando o arquivo é chamado diretamente no terminal.
if __name__ == "__main__":
    # Lê os argumentos do usuário.
    args = parse_args()
    # Interrompe cedo quando o YAML não existe.
    if not Path(args.config).exists():
        raise FileNotFoundError(args.config)
    # Inicia a ingestão com as opções escolhidas.
    run(
        args.config,
        export_parquet=not args.no_export_parquet,
        only=set(args.only) if args.only else None,
        force_refresh_sample=args.force_refresh_sample,
    )
