"""Executa verificações complementares de qualidade nas tabelas Silver."""

# Permite anotações modernas.
from __future__ import annotations

# logging registra o resultado de cada verificação.
import logging
# uuid gera um ID único para o conjunto de testes.
import uuid
# Datas UTC são gravadas na tabela de monitoramento.
from datetime import datetime, timezone

# Cliente oficial do BigQuery.
from google.cloud import bigquery

# Settings lê projeto, datasets e localização.
from src.common.config import Settings
# configure_logging produz logs JSON.
from src.common.logging_utils import configure_logging

# Cria o logger deste módulo.
LOGGER = logging.getLogger(__name__)

# Cada dicionário define o nome, SQL e quantidade máxima aceita de violações.
CHECKS = [
    {
        "name": "municipio_chave_nao_nula",
        "sql": (
            "SELECT COUNT(*) AS violations "
            "FROM `{project}.{silver}.municipio_resultado` "
            "WHERE id_municipio IS NULL"
        ),
        "max_violations": 0,
    },
    {
        "name": "municipio_codigo_sete_digitos",
        "sql": (
            "SELECT COUNT(*) AS violations "
            "FROM `{project}.{silver}.municipio_resultado` "
            "WHERE NOT REGEXP_CONTAINS(id_municipio, r'^\\d{{7}}$')"
        ),
        "max_violations": 0,
    },
    {
        "name": "taxa_municipio_entre_0_100",
        "sql": (
            "SELECT COUNT(*) AS violations "
            "FROM `{project}.{silver}.municipio_resultado` "
            "WHERE taxa_alfabetizacao NOT BETWEEN 0 AND 100"
        ),
        "max_violations": 0,
    },
    {
        "name": "sem_duplicidade_municipio",
        "sql": (
            "SELECT COUNT(*) AS violations FROM ("
            "SELECT ano,id_municipio,serie,rede,COUNT(*) c "
            "FROM `{project}.{silver}.municipio_resultado` "
            "GROUP BY 1,2,3,4 HAVING c>1)"
        ),
        "max_violations": 0,
    },
    {
        "name": "evento_sem_duplicidade",
        "sql": (
            "SELECT COUNT(*) AS violations FROM ("
            "SELECT id_evento,COUNT(*) c "
            "FROM `{project}.{silver}.eventos_indicador_tratados` "
            "GROUP BY 1 HAVING c>1)"
        ),
        "max_violations": 0,
    },
    {
        "name": "integridade_municipio_meta",
        "sql": (
            "SELECT COUNT(*) AS violations "
            "FROM `{project}.{silver}.meta_municipio` m "
            "LEFT JOIN `{project}.{silver}.dim_municipio` d "
            "USING(id_municipio) "
            "WHERE d.id_municipio IS NULL"
        ),
        "max_violations": 0,
    },
]


def ensure_results_table(
    client: bigquery.Client,
    settings: Settings,
) -> None:
    """Cria a tabela que armazena os resultados das verificações."""
    # Monta o ID completo da tabela.
    table_id = (
        f"{settings.project_id}."
        f"{settings.monitoring_dataset}."
        "quality_results"
    )
    # Define o esquema de cada resultado.
    schema = [
        bigquery.SchemaField("run_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("check_name", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("status", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("violations", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("max_violations", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("executed_at", "TIMESTAMP", mode="REQUIRED"),
        bigquery.SchemaField("error_message", "STRING"),
    ]
    # Tenta localizar a tabela antes de criar uma nova.
    try:
        client.get_table(table_id)
    # Qualquer falha de localização leva à tentativa de criação.
    except Exception:  # noqa: BLE001
        # Cria a definição da tabela.
        table = bigquery.Table(table_id, schema=schema)
        # Particiona por dia de execução.
        table.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field="executed_at",
        )
        # Envia a criação para o BigQuery.
        client.create_table(table)


def run() -> None:
    """Executa todos os checks e falha quando houver violação."""
    # Configura logs JSON.
    configure_logging()
    # Lê as configurações do .env.
    settings = Settings.from_env()
    # Cria o cliente BigQuery no projeto do aluno.
    client = bigquery.Client(
        project=settings.project_id,
        location=settings.bq_location,
    )
    # Garante a existência da tabela de resultados.
    ensure_results_table(client, settings)
    # Gera um identificador único para esta bateria de testes.
    run_id = str(uuid.uuid4())
    # Guarda linhas que serão inseridas no final.
    output_rows: list[dict] = []
    # Guarda os nomes dos testes que falharem.
    failures: list[str] = []
    # Percorre a lista declarada no início do arquivo.
    for check in CHECKS:
        # Tenta executar a verificação atual.
        try:
            # Substitui projeto e dataset nos modelos SQL.
            sql = check["sql"].format(
                project=settings.project_id,
                silver=settings.silver_dataset,
            )
            # Executa a consulta e obtém sua única linha.
            row = next(
                iter(
                    client.query(
                        sql,
                        location=settings.bq_location,
                    ).result()
                )
            )
            # Converte a quantidade de violações para inteiro.
            violations = int(row["violations"])
            # Compara o resultado com o máximo permitido.
            status = (
                "PASS"
                if violations <= check["max_violations"]
                else "FAIL"
            )
            # Registra o nome quando o check falhar.
            if status == "FAIL":
                failures.append(check["name"])
            # Prepara a linha de monitoramento.
            output_rows.append(
                {
                    "run_id": run_id,
                    "check_name": check["name"],
                    "status": status,
                    "violations": violations,
                    "max_violations": check["max_violations"],
                    "executed_at": datetime.now(
                        timezone.utc
                    ).isoformat(),
                    "error_message": None,
                }
            )
            # Mostra o resultado no terminal.
            LOGGER.info(
                "Check %s: %s (%s violações)",
                check["name"],
                status,
                violations,
            )
        # Captura erros técnicos, como tabela ausente ou SQL inválido.
        except Exception as exc:  # noqa: BLE001
            # Marca o check como falho.
            failures.append(check["name"])
            # Prepara uma linha com status ERROR.
            output_rows.append(
                {
                    "run_id": run_id,
                    "check_name": check["name"],
                    "status": "ERROR",
                    "violations": -1,
                    "max_violations": check["max_violations"],
                    "executed_at": datetime.now(
                        timezone.utc
                    ).isoformat(),
                    "error_message": str(exc)[:5000],
                }
            )
            # Registra a pilha para diagnóstico.
            LOGGER.exception("Erro no check %s", check["name"])
    # Insere todos os resultados de uma vez.
    errors = client.insert_rows_json(
        (
            f"{settings.project_id}."
            f"{settings.monitoring_dataset}."
            "quality_results"
        ),
        output_rows,
    )
    # Interrompe quando o BigQuery rejeitar a auditoria.
    if errors:
        raise RuntimeError(f"Falha ao persistir resultados: {errors}")
    # Faz a pipeline falhar quando ao menos um teste não passou.
    if failures:
        raise RuntimeError(
            f"Checks com falha: {', '.join(failures)}"
        )


# Executa as verificações quando o módulo é chamado pelo terminal.
if __name__ == "__main__":
    run()
