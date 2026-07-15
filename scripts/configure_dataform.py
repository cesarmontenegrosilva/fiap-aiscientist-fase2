"""Atualiza o ID do projeto usado pelo Dataform."""

# Permite anotações de tipo compatíveis com Python 3.10+.
from __future__ import annotations

# argparse recebe o project-id informado no terminal.
import argparse
# Path lê e grava o arquivo YAML de configuração.
from pathlib import Path


def main() -> None:
    """Substitui somente a linha defaultProject do workflow_settings.yaml."""
    # Cria o leitor de argumentos.
    parser = argparse.ArgumentParser(
        description="Atualiza o projeto GCP do Dataform"
    )
    # Obriga o usuário a informar o ID exato do projeto.
    parser.add_argument("--project-id", required=True)
    # Converte os argumentos da linha de comando.
    args = parser.parse_args()
    # Define o caminho do arquivo que será alterado.
    path = Path("dataform/workflow_settings.yaml")
    # Interrompe com mensagem clara quando o comando foi executado fora da raiz.
    if not path.exists():
        raise FileNotFoundError(
            "Execute este comando na raiz do repositório."
        )
    # Lê o conteúdo atual do YAML.
    text = path.read_text(encoding="utf-8")
    # Prepara uma lista para reconstruir o arquivo linha por linha.
    lines: list[str] = []
    # Percorre todas as linhas existentes.
    for line in text.splitlines():
        # Substitui apenas a configuração do projeto padrão.
        if line.startswith("defaultProject:"):
            line = f"defaultProject: {args.project_id}"
        # Mantém todas as demais linhas sem alteração.
        lines.append(line)
    # Grava o YAML com uma quebra de linha final.
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # Confirma a alteração no terminal.
    print(f"Dataform configurado para o projeto {args.project_id}")


# Executa main somente quando o arquivo é chamado diretamente.
if __name__ == "__main__":
    main()
