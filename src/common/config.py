"""Leitura centralizada das variáveis de ambiente e do catálogo de fontes."""

# Permite retornar Settings nas anotações da própria classe.
from __future__ import annotations

# os lê valores do sistema operacional ou do arquivo .env.
import os
# dataclass reduz código repetitivo na classe de configurações.
from dataclasses import dataclass
# Path oferece leitura de arquivos compatível com Windows e Linux.
from pathlib import Path

# yaml interpreta o arquivo config/sources.yaml.
import yaml
# load_dotenv copia automaticamente as variáveis do arquivo .env.
from dotenv import load_dotenv

# Carrega .env quando ele estiver presente na raiz do projeto.
load_dotenv()


# frozen=True impede alteração acidental das configurações após a criação.
@dataclass(frozen=True)
class Settings:
    """Agrupa as configurações usadas por batch, streaming e qualidade."""

    # ID do projeto GCP criado pelo aluno.
    project_id: str
    # Região dos recursos regionais.
    region: str
    # Localização dos datasets BigQuery.
    bq_location: str
    # Bucket usado por Parquet e Dataflow.
    bucket: str
    # Nome do dataset Bronze.
    bronze_dataset: str
    # Nome do dataset Silver.
    silver_dataset: str
    # Nome do dataset Gold.
    gold_dataset: str
    # Nome do dataset de auditoria.
    monitoring_dataset: str
    # Nome do tópico Pub/Sub.
    pubsub_topic: str
    # Nome da assinatura lida pelo Dataflow.
    pubsub_subscription: str
    # Projeto público de origem.
    source_project: str
    # Dataset público de origem.
    source_dataset: str
    # Teto de bytes cobrados em cada consulta batch.
    maximum_bytes_billed: int

    @classmethod
    def from_env(cls) -> Settings:
        """Cria Settings a partir do .env ou das variáveis do terminal."""
        # Lê e remove espaços do project ID.
        project_id = os.getenv("GCP_PROJECT_ID", "").strip()
        # O projeto é obrigatório porque ele recebe as tabelas e paga as consultas.
        if not project_id:
            raise ValueError(
                "Defina GCP_PROJECT_ID no ambiente ou no arquivo .env"
            )
        # Gera um nome padrão de bucket quando GCS_BUCKET não foi definido.
        bucket = os.getenv(
            "GCS_BUCKET",
            f"{project_id}-alfabetizacao-lake",
        )
        # Devolve uma instância imutável com todos os valores.
        return cls(
            project_id=project_id,
            region=os.getenv("GCP_REGION", "us-central1"),
            bq_location=os.getenv("BIGQUERY_LOCATION", "US"),
            bucket=bucket,
            bronze_dataset=os.getenv(
                "BQ_DATASET_BRONZE",
                "alfabetizacao_bronze",
            ),
            silver_dataset=os.getenv(
                "BQ_DATASET_SILVER",
                "alfabetizacao_silver",
            ),
            gold_dataset=os.getenv(
                "BQ_DATASET_GOLD",
                "alfabetizacao_gold",
            ),
            monitoring_dataset=os.getenv(
                "BQ_DATASET_MONITORING",
                "alfabetizacao_monitoring",
            ),
            pubsub_topic=os.getenv(
                "PUBSUB_TOPIC",
                "alfabetizacao-indicadores",
            ),
            pubsub_subscription=os.getenv(
                "PUBSUB_SUBSCRIPTION",
                "alfabetizacao-indicadores-dataflow",
            ),
            source_project=os.getenv(
                "SOURCE_PROJECT",
                "basedosdados",
            ),
            source_dataset=os.getenv(
                "SOURCE_DATASET",
                "br_inep_avaliacao_alfabetizacao",
            ),
            maximum_bytes_billed=int(
                os.getenv(
                    "MAXIMUM_BYTES_BILLED",
                    str(10 * 1024**3),
                )
            ),
        )


def load_sources(path: str | Path = "config/sources.yaml") -> dict:
    """Lê o catálogo YAML que define fontes e estratégias de ingestão."""
    # Abre o arquivo com codificação UTF-8.
    with Path(path).open("r", encoding="utf-8") as stream:
        # safe_load evita construir objetos Python inseguros a partir do YAML.
        return yaml.safe_load(stream)
