"""Configuração de logs JSON para terminal, Cloud Logging e auditoria."""

# Permite anotações modernas.
from __future__ import annotations

# json converte o dicionário do log em uma linha estruturada.
import json
# logging é a biblioteca padrão usada por todos os módulos.
import logging
# sys fornece stdout para o StreamHandler.
import sys
# Datas UTC evitam ambiguidade entre ambientes.
from datetime import datetime, timezone


class JsonFormatter(logging.Formatter):
    """Transforma cada registro de log em um JSON simples."""

    def format(self, record: logging.LogRecord) -> str:
        """Monta o conteúdo que será enviado ao terminal ou Cloud Logging."""
        # Cria os campos básicos presentes em todos os registros.
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "severity": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Acrescenta campos técnicos quando eles foram informados em extra.
        for field in (
            "run_id",
            "pipeline",
            "table",
            "rows",
            "action",
            "duration_seconds",
        ):
            # hasattr evita tentar ler campos que não existem.
            if hasattr(record, field):
                # Copia o campo para o JSON final.
                payload[field] = getattr(record, field)
        # Inclui a pilha de erro quando LOGGER.exception() foi usado.
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        # Serializa o dicionário sem escapar caracteres em português.
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level: int = logging.INFO) -> None:
    """Substitui o formato padrão do logging pelo formato JSON."""
    # Cria um handler que escreve no stdout.
    handler = logging.StreamHandler(sys.stdout)
    # Aplica o formatador definido acima.
    handler.setFormatter(JsonFormatter())
    # Obtém o logger raiz para configurar todos os módulos.
    root = logging.getLogger()
    # Remove handlers anteriores para evitar mensagens duplicadas.
    root.handlers.clear()
    # Adiciona o novo handler.
    root.addHandler(handler)
    # Define o nível mínimo de severidade.
    root.setLevel(level)
