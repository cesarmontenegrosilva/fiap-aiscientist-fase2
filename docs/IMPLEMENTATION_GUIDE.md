# Guia de implementação

1. Instale Python, Git, gcloud, Terraform, Node.js e VS Code.
2. Execute `gcloud auth login` e `gcloud auth application-default login`.
3. No Git Bash, rode `scripts/setup_gcp.sh` com projeto, bucket e billing account.
4. Crie `.venv` e instale `pip install -e ".[dev]"`.
5. Execute `terraform init`, `plan` e `apply`.
6. Rode `scripts/transferir_dados_inep.py` para criar a Bronze e `alunos_amostra`.
7. Rode `scripts/run_dataform.sh` para criar Silver e Gold.
8. Rode `python -m src.quality.run_checks`.
9. Inicie Dataflow, publique eventos e pare Dataflow após a demonstração.
10. Simule a limpeza e depois exclua recursos e projeto com `limpar_gcp.ps1 -DeleteProject`.

Para comandos completos, consulte `PASSO_A_PASSO_EXECUCAO_E_EXCLUSAO.txt`.
