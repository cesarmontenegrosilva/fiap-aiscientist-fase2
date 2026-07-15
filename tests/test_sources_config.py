"""Testes simples do catálogo de fontes usado pela ingestão batch."""

# Importa a função que lê o arquivo YAML das fontes.
from src.common.config import load_sources


def test_all_required_sources_are_configured() -> None:
    """Confirma que todas as entidades obrigatórias estão configuradas."""
    # Carrega o catálogo principal do projeto.
    config = load_sources("config/sources.yaml")
    # Cria um conjunto com os nomes das fontes para facilitar a comparação.
    names = {source["name"] for source in config["sources"]}
    # Verifica se as tabelas exigidas pelo desafio estão presentes.
    assert {
        "uf",
        "municipio",
        "alunos_amostra",
        "meta_alfabetizacao_brasil",
        "meta_alfabetizacao_uf",
        "meta_alfabetizacao_municipio",
    }.issubset(names)


def test_student_table_uses_one_time_physical_sample() -> None:
    """Garante que a tabela de alunos não seja carregada integralmente."""
    # Carrega novamente o catálogo para localizar a configuração da amostra.
    config = load_sources("config/sources.yaml")
    # Seleciona apenas a entrada chamada alunos_amostra.
    source = next(item for item in config["sources"] if item["name"] == "alunos_amostra")
    # Confirma que a estratégia é criar a amostra física apenas uma vez.
    assert source["mode"] == "physical_sample_once"
    # Confirma o tamanho padrão solicitado para a demonstração.
    assert source["sample_rows"] == 500
    # Confirma que TABLESAMPLE será usado para reduzir a leitura inicial.
    assert 0 < source["sample_percent"] <= 100
