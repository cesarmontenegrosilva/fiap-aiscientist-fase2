"""Pipeline Apache Beam que valida Pub/Sub e grava válido/rejeitado no BigQuery."""

# Permite anotações modernas.
from __future__ import annotations

# argparse separa parâmetros da aplicação e do Apache Beam.
import argparse
# json interpreta o corpo da mensagem recebida.
import json
# Datas UTC registram o horário de processamento.
from datetime import datetime, timezone
# Any representa mensagens Pub/Sub ou bytes nos testes locais.
from typing import Any

# Apache Beam fornece o modelo unificado de processamento.
import apache_beam as beam
# Dispositions controlam criação e escrita no BigQuery.
from apache_beam.io.gcp.bigquery import BigQueryDisposition
# PipelineOptions recebe parâmetros do DataflowRunner.
from apache_beam.options.pipeline_options import (
    PipelineOptions,
    SetupOptions,
    StandardOptions,
)
# ValidationError identifica violações do contrato Pydantic.
from pydantic import ValidationError

# Modelo de validação compartilhado com os testes.
from src.streaming.models import IndicatorEvent

# Esquema da tabela de eventos válidos no BigQuery.
VALID_SCHEMA = (
    "id_evento:STRING,id_municipio:STRING,sigla_uf:STRING,ano:INTEGER,"
    "rede:STRING,serie:STRING,taxa_alfabetizacao:FLOAT,"
    "meta_alfabetizacao:FLOAT,tipo_evento:STRING,fonte:STRING,"
    "data_evento:TIMESTAMP,data_processamento:TIMESTAMP,"
    "pubsub_message_id:STRING"
)
# Esquema da tabela de eventos rejeitados.
REJECTED_SCHEMA = (
    "payload:STRING,error_message:STRING,data_processamento:TIMESTAMP,"
    "pubsub_message_id:STRING"
)


class ParseAndValidate(beam.DoFn):
    """Separa cada mensagem em saída válida ou inválida."""

    # Nome da saída lateral de registros válidos.
    VALID = "valid"
    # Nome da saída lateral de registros inválidos.
    INVALID = "invalid"

    def process(self, message: Any):
        """Interpreta JSON, valida contrato e produz uma das duas saídas."""
        # Recupera o ID atribuído pelo Pub/Sub quando disponível.
        message_id = getattr(message, "message_id", None)
        # Extrai bytes do PubsubMessage ou usa o valor recebido diretamente.
        raw = message.data if hasattr(message, "data") else message
        # Tenta transformar e validar a mensagem.
        try:
            # Decodifica bytes e converte JSON para dicionário.
            payload = json.loads(
                raw.decode("utf-8") if isinstance(raw, bytes) else raw
            )
            # Aplica todas as regras do modelo IndicatorEvent.
            event = IndicatorEvent.model_validate(payload)
            # Converte o modelo validado para um dicionário serializável.
            row = event.model_dump(mode="json")
            # Garante o formato ISO da data do evento.
            row["data_evento"] = event.data_evento.isoformat()
            # Registra o momento em que o Dataflow processou a mensagem.
            row["data_processamento"] = datetime.now(
                timezone.utc
            ).isoformat()
            # Preserva o ID técnico do Pub/Sub.
            row["pubsub_message_id"] = message_id
            # Envia a linha para a saída válida.
            yield beam.pvalue.TaggedOutput(self.VALID, row)
        # Captura erros esperados de JSON, codificação, contrato ou tipo.
        except (
            json.JSONDecodeError,
            UnicodeDecodeError,
            ValidationError,
            TypeError,
        ) as exc:
            # Prepara uma linha para diagnóstico e dead-letter.
            rejected = {
                "payload": (
                    raw.decode("utf-8", errors="replace")
                    if isinstance(raw, bytes)
                    else str(raw)
                ),
                "error_message": str(exc)[:5000],
                "data_processamento": datetime.now(
                    timezone.utc
                ).isoformat(),
                "pubsub_message_id": message_id,
            }
            # Envia a linha para a saída inválida.
            yield beam.pvalue.TaggedOutput(self.INVALID, rejected)


def run(argv: list[str] | None = None) -> None:
    """Monta e executa a pipeline com DirectRunner ou DataflowRunner."""
    # Cria o parser dos argumentos específicos desta aplicação.
    parser = argparse.ArgumentParser()
    # Exige a assinatura Pub/Sub de entrada.
    parser.add_argument("--input_subscription", required=True)
    # Exige a tabela BigQuery de eventos válidos.
    parser.add_argument("--output_table", required=True)
    # Exige a tabela BigQuery de eventos rejeitados.
    parser.add_argument("--rejected_table", required=True)
    # Separa argumentos conhecidos dos argumentos gerais do Beam.
    known_args, pipeline_args = parser.parse_known_args(argv)

    # Cria as opções do Apache Beam.
    options = PipelineOptions(pipeline_args)
    # Salva a sessão principal para disponibilizar imports nos workers.
    options.view_as(SetupOptions).save_main_session = True
    # Marca a execução como streaming.
    options.view_as(StandardOptions).streaming = True

    # Cria e fecha automaticamente o contexto da pipeline.
    with beam.Pipeline(options=options) as pipeline:
        # Lê mensagens e seus atributos da assinatura Pub/Sub.
        messages = pipeline | "Ler PubSub" >> beam.io.ReadFromPubSub(
            subscription=known_args.input_subscription,
            with_attributes=True,
        )
        # Aplica a função de validação e expõe duas coleções.
        parsed = (
            messages
            | "Validar JSON"
            >> beam.ParDo(ParseAndValidate()).with_outputs(
                ParseAndValidate.VALID,
                ParseAndValidate.INVALID,
            )
        )
        # Grava eventos válidos na tabela Bronze principal.
        _ = (
            parsed.valid
            | "Gravar eventos válidos"
            >> beam.io.WriteToBigQuery(
                known_args.output_table,
                schema=VALID_SCHEMA,
                create_disposition=BigQueryDisposition.CREATE_NEVER,
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS,
                insert_retry_strategy="RETRY_ON_TRANSIENT_ERROR",
            )
        )
        # Grava mensagens inválidas na tabela de rejeitados.
        _ = (
            parsed.invalid
            | "Gravar rejeitados"
            >> beam.io.WriteToBigQuery(
                known_args.rejected_table,
                schema=REJECTED_SCHEMA,
                create_disposition=BigQueryDisposition.CREATE_NEVER,
                write_disposition=BigQueryDisposition.WRITE_APPEND,
                method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS,
                insert_retry_strategy="RETRY_ON_TRANSIENT_ERROR",
            )
        )


# Executa a pipeline quando o módulo é chamado diretamente.
if __name__ == "__main__":
    run()
