# Relatório de validação local

Eu validei o conteúdo do repositório antes de gerar o pacote final.

## Resultados

- **Python:** todos os módulos de `src/`, `scripts/` e `tests/` foram compilados sem erro.
- **Testes unitários:** 7 testes aprovados com `pytest`.
- **Lint:** `ruff` aprovado sem erros.
- **Bash:** todos os arquivos `scripts/*.sh` passaram em `bash -n`.
- **JSON e YAML:** todos os arquivos foram lidos e validados sem erro.
- **Terraform:** os arquivos `.tf` foram analisados com `python-hcl2` e não apresentaram erro de sintaxe HCL.
- **Dataform:** compilação concluída com 15 tabelas/visões e 26 assertions, totalizando 41 ações.
- **DOCX:** 4 páginas renderizadas e inspecionadas visualmente, sem sobreposição ou corte.
- **PPTX:** 10 slides renderizados e inspecionados visualmente, sem overflow.

## Limites da validação

O Terraform CLI não estava disponível no ambiente de geração, por isso não executei `terraform validate` nem `terraform plan`. A análise HCL confirma a sintaxe, mas a aplicação real ainda depende das versões dos providers, permissões da conta e políticas do projeto GCP.

Nenhum recurso foi criado em uma conta real do Google Cloud. A implantação depende do `project_id`, conta de faturamento, credenciais e permissões do aluno. O repositório não cria recursos automaticamente ao ser baixado.

O script PowerShell foi revisado estruturalmente, mas não foi executado neste ambiente Linux. Antes da exclusão real, deve ser usado primeiro com `-DryRun`.
