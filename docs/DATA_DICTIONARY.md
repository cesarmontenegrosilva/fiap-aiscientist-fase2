# Dicionário resumido

## Bronze

- `uf`: resultados por unidade federativa.
- `municipio`: resultados por município.
- `alunos_amostra`: amostra física de até 500 registros da tabela pública de alunos.
- `meta_alfabetizacao_brasil`: metas nacionais.
- `meta_alfabetizacao_uf`: metas estaduais.
- `meta_alfabetizacao_municipio`: metas municipais.
- `diretorio_municipio`: nomes, UFs e regiões dos municípios.
- `eventos_indicador`: eventos streaming válidos.
- `eventos_rejeitados`: mensagens que não passaram no contrato.

As tabelas batch recebem `_ingested_at`, `_ingestion_run_id` e `_source_table`.

## Silver

A Silver padroniza ano, códigos IBGE, nomes, tipos e percentuais. Também remove duplicidades e integra resultados, metas e território.

## Gold

- `indicador_municipio`: resultado e meta municipal.
- `indicador_uf`: consolidação estadual.
- `situacao_atual_municipio`: visão mais recente por município.
- `evolucao_temporal`: série histórica.
- `ranking_municipios`: classificação nacional e estadual.
- `resumo_brasil`: consolidação nacional.
- `features_ml`: variáveis preparadas para modelos futuros.
