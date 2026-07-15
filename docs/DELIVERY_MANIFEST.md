# Entregáveis

Este pacote contém a aplicação, os documentos e os procedimentos necessários para reproduzir e remover a demonstração.

- `README.md`: explicação principal, arquitetura, custo, implantação e exclusão.
- `docs/deliverables/Manual_Implementacao_Tech_Challenge_Alfabetizacao_GCP.docx`: manual simplificado em linguagem de aluno.
- `docs/deliverables/Apresentacao_Tech_Challenge_Alfabetizacao_GCP.pptx`: apresentação executiva de 10 slides.
- `docs/VIDEO_SCRIPT.md`: roteiro de até cinco minutos.
- `docs/FONTES_DADOS_URLS.txt`: URL e URI BigQuery exatas de cada fonte.
- `docs/ONDE_COLOCAR_PROJECT_ID.txt`: pontos em que o ID do projeto deve ser informado.
- `docs/PASSO_A_PASSO_EXECUCAO_E_EXCLUSAO.txt`: sequência desde a criação até a exclusão do projeto.
- `docs/MAPA_ARQUIVOS_E_FERRAMENTAS.txt`: responsabilidade de cada componente e ferramenta.
- `config/sources.yaml`: estratégia de cópia integral das tabelas pequenas e criação única de `alunos_amostra`.
- `src/` e `scripts/`: ingestão batch, streaming, qualidade, configuração e limpeza comentadas.
- `dataform/`: Silver, Gold e assertions.
- `terraform/`: infraestrutura como código.
- `tests/`: testes unitários.
