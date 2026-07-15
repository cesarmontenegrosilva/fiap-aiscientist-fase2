"""Funções pequenas compartilhadas pelos códigos que usam BigQuery."""

# Permite anotações de tipo modernas no Python 3.10+.
from __future__ import annotations

# Importa o cliente oficial do BigQuery.
from google.cloud import bigquery


def query_job_config(
    maximum_bytes_billed: int,
    labels: dict[str, str] | None = None,
) -> bigquery.QueryJobConfig:
    """Cria uma configuração padrão de consulta com controle de custo."""
    # Devolve um objeto usado por client.query().
    return bigquery.QueryJobConfig(
        # Obriga o uso de GoogleSQL, que é o padrão atual do BigQuery.
        use_legacy_sql=False,
        # Interrompe a consulta se a estimativa ultrapassar o teto definido.
        maximum_bytes_billed=maximum_bytes_billed,
        # Adiciona rótulos para facilitar auditoria e análise de custo.
        labels=labels or {},
    )


def quote_table(project: str, dataset: str, table: str) -> str:
    """Monta uma referência BigQuery protegida por crases."""
    # Retorna o formato `projeto.dataset.tabela` aceito pelo GoogleSQL.
    return f"`{project}.{dataset}.{table}`"
