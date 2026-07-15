"""Contrato e validações dos eventos simulados de alfabetização."""

# Permite anotações modernas.
from __future__ import annotations

# datetime e timezone validam o horário do evento.
from datetime import datetime, timezone

# BaseModel cria o contrato; Field define limites; validator normaliza valores.
from pydantic import BaseModel, ConfigDict, Field, field_validator

# Conjunto oficial das 27 siglas estaduais aceitas pelo contrato.
VALID_UFS = {
    "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO",
    "MA", "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI",
    "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO",
}


class IndicatorEvent(BaseModel):
    """Representa uma atualização municipal recebida pelo Pub/Sub."""

    # Rejeita campos extras, evitando receber dados pessoais não previstos.
    model_config = ConfigDict(extra="forbid")

    # Identificador único do evento.
    id_evento: str = Field(min_length=1)
    # Código IBGE municipal com exatamente sete dígitos.
    id_municipio: str = Field(pattern=r"^\d{7}$")
    # Sigla da unidade federativa.
    sigla_uf: str
    # Ano aceito pelo projeto e por possíveis metas futuras.
    ano: int = Field(ge=2023, le=2035)
    # Rede de ensino do indicador.
    rede: str = Field(min_length=1)
    # Série escolar associada.
    serie: str = Field(min_length=1)
    # Percentual observado, restrito ao intervalo válido.
    taxa_alfabetizacao: float = Field(ge=0, le=100)
    # Meta é opcional, mas também deve estar entre 0 e 100.
    meta_alfabetizacao: float | None = Field(default=None, ge=0, le=100)
    # Tipo padrão usado pelo simulador.
    tipo_evento: str = "ATUALIZACAO_INDICADOR"
    # Fonte padrão deixa claro que não é uma atualização oficial.
    fonte: str = "SIMULADOR_TECH_CHALLENGE"
    # Horário em que o evento foi gerado.
    data_evento: datetime

    @field_validator("sigla_uf")
    @classmethod
    def validate_uf(cls, value: str) -> str:
        """Padroniza a UF em maiúsculas e rejeita siglas desconhecidas."""
        # Remove espaços e converte para maiúsculas.
        normalized = value.strip().upper()
        # Verifica a presença no conjunto oficial.
        if normalized not in VALID_UFS:
            raise ValueError("sigla_uf inválida")
        # Devolve o valor padronizado.
        return normalized

    @field_validator("data_evento")
    @classmethod
    def validate_event_time(cls, value: datetime) -> datetime:
        """Garante timezone e impede eventos com data futura."""
        # Datas sem timezone são interpretadas como UTC.
        normalized = (
            value
            if value.tzinfo
            else value.replace(tzinfo=timezone.utc)
        )
        # Rejeita eventos posteriores ao momento da validação.
        if normalized > datetime.now(timezone.utc):
            raise ValueError("data_evento não pode estar no futuro")
        # Devolve a data pronta para gravação.
        return normalized
