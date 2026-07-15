#!/usr/bin/env bash
# Interrompe ao primeiro erro, rejeita variáveis vazias e falhas em pipes.
set -euo pipefail

# Localiza a raiz do repositório a partir da pasta scripts/.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Entra na pasta que contém o projeto Dataform.
cd "$REPO_ROOT/dataform"

# Compila os modelos para identificar erros de SQL ou dependência antes da execução.
npx --yes -p @dataform/cli@3.0.26 dataform compile .
# Materializa Silver e Gold e executa as assertions de qualidade.
npx --yes -p @dataform/cli@3.0.26 dataform run .
