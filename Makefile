# Usa Bash para os alvos que executam scripts .sh.
SHELL := /bin/bash
# Permite trocar o executável Python com: make PYTHON=python3.
PYTHON ?= python

# Declara alvos que não representam arquivos físicos.
.PHONY: setup test lint format infra-init infra-plan infra-apply batch stream-dataflow publish publish-invalid quality dataform deploy-batch schedule-batch smoke stop-stream cleanup-dry-run cleanup cleanup-project zip

# Cria o ambiente virtual e instala dependências de desenvolvimento.
setup:
	$(PYTHON) -m venv .venv
	. .venv/bin/activate && pip install --upgrade pip && pip install -e '.[dev]'

# Executa análise estática dos códigos Python.
lint:
	ruff check src scripts tests

# Formata os códigos Python.
format:
	ruff format src scripts tests

# Executa os testes unitários.
test:
	pytest

# Baixa os providers do Terraform.
infra-init:
	terraform -chdir=terraform init

# Mostra os recursos que serão criados ou alterados.
infra-plan:
	terraform -chdir=terraform plan

# Cria a infraestrutura no GCP.
infra-apply:
	terraform -chdir=terraform apply

# Executa a Bronze sem Parquet; alunos_amostra será criada uma única vez.
batch:
	$(PYTHON) scripts/transferir_dados_inep.py --project-id $$GCP_PROJECT_ID --sem-parquet

# Inicia o pipeline streaming no Dataflow.
stream-dataflow:
	bash scripts/run_dataflow.sh

# Publica 30 eventos válidos.
publish:
	$(PYTHON) -m src.streaming.publisher --count 30 --interval 1

# Publica eventos com 20% de mensagens inválidas.
publish-invalid:
	$(PYTHON) -m src.streaming.publisher --count 20 --interval 0.5 --invalid-rate 0.2

# Executa os checks Python de qualidade.
quality:
	$(PYTHON) -m src.quality.run_checks

# Materializa Silver, Gold e assertions.
dataform:
	bash scripts/run_dataform.sh

# Constrói e executa o Cloud Run Job batch.
deploy-batch:
	bash scripts/build_and_deploy_batch.sh

# Agenda o job batch semanalmente.
schedule-batch:
	bash scripts/schedule_batch.sh

# Executa uma verificação rápida da aplicação.
smoke:
	bash scripts/smoke_test.sh

# Cancela o Dataflow para interromper custos.
stop-stream:
	bash scripts/stop_dataflow.sh

# Simula a limpeza sem apagar recursos.
cleanup-dry-run:
	powershell -ExecutionPolicy Bypass -File scripts/limpar_gcp.ps1 -ProjectId $$GCP_PROJECT_ID -Bucket $$GCS_BUCKET -DryRun

# Apaga recursos, mas mantém o projeto.
cleanup:
	powershell -ExecutionPolicy Bypass -File scripts/limpar_gcp.ps1 -ProjectId $$GCP_PROJECT_ID -Bucket $$GCS_BUCKET

# Apaga recursos e solicita a exclusão do projeto temporário.
cleanup-project:
	powershell -ExecutionPolicy Bypass -File scripts/limpar_gcp.ps1 -ProjectId $$GCP_PROJECT_ID -Bucket $$GCS_BUCKET -DeleteProject

# Cria um ZIP sem ambientes, providers, state e node_modules.
zip:
	cd .. && zip -r tech-challenge-alfabetizacao-gcp.zip tech-challenge-alfabetizacao-gcp -x '*/.venv/*' '*/.terraform/*' '*/terraform.tfstate*' '*/node_modules/*' '*/__pycache__/*'
