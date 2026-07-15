"""Testes unitários das regras aplicadas aos eventos streaming."""

# Datas são usadas para criar eventos válidos e futuros.
from datetime import datetime, timedelta, timezone

# pytest oferece a verificação de exceções esperadas.
import pytest
# ValidationError é o erro esperado quando o contrato é violado.
from pydantic import ValidationError

# Importa o modelo que será testado.
from src.streaming.models import IndicatorEvent


def valid_payload() -> dict:
    """Cria um exemplo válido que pode ser alterado em cada teste."""
    # Devolve todos os campos obrigatórios do contrato.
    return {
        "id_evento": "evt-1",
        "id_municipio": "2611606",
        "sigla_uf": "pe",
        "ano": 2025,
        "rede": "publica",
        "serie": "2",
        "taxa_alfabetizacao": 72.5,
        "meta_alfabetizacao": 75.0,
        "data_evento": (
            datetime.now(timezone.utc) - timedelta(seconds=1)
        ).isoformat(),
    }


def test_valid_event_normalizes_uf() -> None:
    """Confirma que uma UF minúscula é padronizada."""
    # Valida o exemplo básico.
    event = IndicatorEvent.model_validate(valid_payload())
    # Espera o valor final em maiúsculas.
    assert event.sigla_uf == "PE"


def test_invalid_percentage() -> None:
    """Confirma que percentuais acima de 100 são rejeitados."""
    # Copia o exemplo válido.
    payload = valid_payload()
    # Introduz o erro de faixa.
    payload["taxa_alfabetizacao"] = 120
    # Espera uma falha de validação.
    with pytest.raises(ValidationError):
        IndicatorEvent.model_validate(payload)


def test_invalid_municipality_code() -> None:
    """Confirma que o município precisa ter sete dígitos."""
    # Copia o exemplo válido.
    payload = valid_payload()
    # Introduz uma chave incorreta.
    payload["id_municipio"] = "123"
    # Espera uma falha de validação.
    with pytest.raises(ValidationError):
        IndicatorEvent.model_validate(payload)


def test_future_event_is_rejected() -> None:
    """Confirma que eventos futuros não entram na Bronze válida."""
    # Copia o exemplo válido.
    payload = valid_payload()
    # Coloca a data um dia no futuro.
    payload["data_evento"] = (
        datetime.now(timezone.utc) + timedelta(days=1)
    ).isoformat()
    # Espera uma falha de validação.
    with pytest.raises(ValidationError):
        IndicatorEvent.model_validate(payload)


def test_extra_field_is_rejected() -> None:
    """Confirma que campos pessoais não previstos são rejeitados."""
    # Copia o exemplo válido.
    payload = valid_payload()
    # Introduz um campo proibido pelo contrato.
    payload["nome_aluno"] = "não permitido"
    # Espera uma falha de validação.
    with pytest.raises(ValidationError):
        IndicatorEvent.model_validate(payload)
