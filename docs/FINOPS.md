# FinOps e controle de custos

As decisões de custo que eu apliquei foram:

1. `alunos_amostra` é criada fisicamente uma única vez.
2. A criação usa `TABLESAMPLE` antes do limite de 500 linhas.
3. Silver e Gold usam a tabela local, sem consultar novamente os microdados públicos.
4. Cada consulta batch possui `maximum_bytes_billed` de 10 GiB.
5. O Dataflow usa no máximo dois workers e deve ser desligado após a demonstração.
6. Parquet no Cloud Storage é opcional durante os testes.
7. O Terraform pode criar um alerta de orçamento.
8. Os scripts de limpeza removem recursos e podem excluir o projeto temporário.

A amostra serve para demonstrar a engenharia da solução. Ela não deve ser usada para conclusões estatísticas sobre o Brasil.
