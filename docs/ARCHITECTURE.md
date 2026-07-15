# Arquitetura da solução

Eu usei uma arquitetura serverless no GCP para reduzir a necessidade de administrar servidores.

## Batch

`BigQuery público -> Python -> BigQuery Bronze -> Dataform Silver -> Dataform Gold`

As tabelas pequenas são copiadas por completo. A tabela de alunos gera uma amostra física de até 500 linhas apenas na primeira execução.

## Streaming

`Publisher Python -> Pub/Sub -> Dataflow -> BigQuery Bronze`

O streaming é uma simulação acadêmica. Eventos válidos vão para `eventos_indicador` e inválidos vão para `eventos_rejeitados`.

## Camadas

- **Bronze:** dados brutos, metadados de ingestão e histórico.
- **Silver:** limpeza, tipos, nulos, chaves, deduplicação e integração.
- **Gold:** indicadores municipais e estaduais, metas, evolução, ranking e features para IA.

## Motivo das escolhas

BigQuery e Dataform simplificam o processamento SQL. Pub/Sub e Dataflow demonstram streaming. Terraform torna a infraestrutura reproduzível e removível no final.
