"""Arquivo mínimo usado pelo Apache Beam para empacotar o projeto nos workers."""

# find_packages localiza os módulos dentro de src; setup cria o pacote.
from setuptools import find_packages, setup

# Registra o pacote que será enviado aos workers do Dataflow.
setup(
    # Nome técnico do pacote.
    name="alfabetizacao-pipeline",
    # Versão acadêmica da implementação.
    version="0.1.0",
    # Inclui todos os pacotes Python encontrados no repositório.
    packages=find_packages(),
)
