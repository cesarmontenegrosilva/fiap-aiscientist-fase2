"""Publica eventos simulados no Pub/Sub para demonstrar o fluxo streaming."""

# Permite anotações modernas.
from __future__ import annotations

# argparse lê quantidade, intervalo e taxa de erro do terminal.
import argparse
# json converte os eventos Python em mensagens UTF-8.
import json
# random escolhe municípios e valores para a simulação.
import random
# time cria o intervalo entre mensagens.
import time
# uuid gera um identificador único para cada evento.
import uuid
# Datas UTC são usadas no campo data_evento.
from datetime import datetime, timedelta, timezone

# Cliente oficial do Google Pub/Sub.
from google.cloud import pubsub_v1

# Settings lê projeto e tópico do arquivo .env.
from src.common.config import Settings

# Pequena lista de municípios usada apenas na demonstração.
MUNICIPIOS = [
    ("2611606", "PE"),
    ("2607901", "PE"),
    ("3550308", "SP"),
    ("3304557", "RJ"),
    ("2927408", "BA"),
    ("2304400", "CE"),
    ("1302603", "AM"),
    ("3106200", "MG"),
    ("4314902", "RS"),
    ("4106902", "PR"),
]


def build_event() -> dict:
    """Cria um evento válido com valores simulados."""
    # Escolhe aleatoriamente um município e sua UF correspondente.
    id_municipio, sigla_uf = random.choice(MUNICIPIOS)
    # Gera uma taxa entre 45% e 92%.
    taxa = round(random.uniform(45, 92), 2)
    # Gera uma meta próxima da taxa e limita o máximo a 100%.
    meta = round(min(100, taxa + random.uniform(-5, 10)), 2)
    # Devolve o dicionário que será serializado em JSON.
    return {
        "id_evento": str(uuid.uuid4()),
        "id_municipio": id_municipio,
        "sigla_uf": sigla_uf,
        "ano": 2025,
        "rede": "publica",
        "serie": "2",
        "taxa_alfabetizacao": taxa,
        "meta_alfabetizacao": meta,
        "tipo_evento": "ATUALIZACAO_INDICADOR",
        "fonte": "SIMULADOR_TECH_CHALLENGE",
        "data_evento": (
            datetime.now(timezone.utc) - timedelta(seconds=1)
        ).isoformat(),
    }


def corrupt_event(event: dict) -> dict:
    """Cria intencionalmente um evento inválido para testar a dead-letter."""
    # Copia o dicionário para não alterar o evento original.
    corrupted = event.copy()
    # Escolhe um tipo de erro de qualidade.
    corruption = random.choice(
        ["municipio", "taxa", "uf", "futuro", "campo_extra"]
    )
    # Produz um código municipal com tamanho incorreto.
    if corruption == "municipio":
        corrupted["id_municipio"] = "123"
    # Produz um percentual acima de 100.
    elif corruption == "taxa":
        corrupted["taxa_alfabetizacao"] = 150
    # Produz uma UF inexistente.
    elif corruption == "uf":
        corrupted["sigla_uf"] = "XX"
    # Produz uma data posterior ao momento atual.
    elif corruption == "futuro":
        corrupted["data_evento"] = (
            datetime.now(timezone.utc) + timedelta(days=1)
        ).isoformat()
    # Produz um campo não permitido pelo contrato.
    else:
        corrupted["nome_aluno"] = "campo proibido pelo contrato"
    # Devolve o evento alterado.
    return corrupted


def publish(count: int, interval: float, invalid_rate: float) -> None:
    """Publica a quantidade solicitada de mensagens e aguarda confirmação."""
    # Garante que a proporção de inválidos seja um valor probabilístico válido.
    if not 0 <= invalid_rate <= 1:
        raise ValueError("invalid_rate deve estar entre 0 e 1")
    # Lê projeto e tópico do .env.
    settings = Settings.from_env()
    # Cria o cliente publicador.
    publisher = pubsub_v1.PublisherClient()
    # Monta o caminho completo do tópico.
    topic_path = publisher.topic_path(
        settings.project_id,
        settings.pubsub_topic,
    )
    # Guarda os objetos Future devolvidos pelo Pub/Sub.
    futures = []
    # Repete a publicação conforme --count.
    for index in range(count):
        # Cria um evento inicialmente válido.
        event = build_event()
        # Decide aleatoriamente se a mensagem será corrompida.
        invalid = random.random() < invalid_rate
        # Aplica uma corrupção quando necessário.
        if invalid:
            event = corrupt_event(event)
        # Converte o dicionário para bytes UTF-8.
        data = json.dumps(
            event,
            ensure_ascii=False,
        ).encode("utf-8")
        # Publica dados e atributos úteis para observabilidade.
        future = publisher.publish(
            topic_path,
            data=data,
            event_type=event.get("tipo_evento", "DESCONHECIDO"),
            municipality=event.get("id_municipio", "SEM_CHAVE"),
        )
        # Guarda o Future para confirmar a publicação no final.
        futures.append(future)
        # Define uma descrição legível para o terminal.
        status = "INVÁLIDO" if invalid else "válido"
        # Mostra progresso e chave do evento.
        print(
            f"[{index + 1}/{count}] publicado {status}: "
            f"{event.get('id_evento')} - {event.get('id_municipio')}"
        )
        # Aguarda o intervalo apenas quando ele for maior que zero.
        if interval:
            time.sleep(interval)
    # Aguarda a confirmação do Pub/Sub para todas as mensagens.
    for future in futures:
        future.result(timeout=60)


def parse_args() -> argparse.Namespace:
    """Lê opções da simulação no terminal."""
    # Cria o parser principal.
    parser = argparse.ArgumentParser(
        description="Publicador de eventos simulados"
    )
    # Quantidade padrão de mensagens.
    parser.add_argument("--count", type=int, default=20)
    # Intervalo padrão de um segundo entre mensagens.
    parser.add_argument("--interval", type=float, default=1.0)
    # Percentual opcional de mensagens inválidas.
    parser.add_argument(
        "--invalid-rate",
        type=float,
        default=0.0,
        help="Proporção de mensagens inválidas, entre 0 e 1.",
    )
    # Devolve os argumentos normalizados.
    return parser.parse_args()


# Executa a simulação somente quando o arquivo é chamado diretamente.
if __name__ == "__main__":
    # Lê as opções do usuário.
    args = parse_args()
    # Inicia a publicação.
    publish(args.count, args.interval, args.invalid_rate)
