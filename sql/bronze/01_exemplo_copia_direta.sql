-- Substitua SEU_PROJECT_ID pelo ID real do seu projeto.
-- O dataset de destino deve estar na localização US.
-- Este exemplo sobrescreve a tabela. O pipeline Python preserva snapshots históricos.

CREATE SCHEMA IF NOT EXISTS `SEU_PROJECT_ID.alfabetizacao_bronze`
OPTIONS(location = "US");

CREATE OR REPLACE TABLE `SEU_PROJECT_ID.alfabetizacao_bronze.uf_copia_simples` AS
SELECT
  *,
  CURRENT_TIMESTAMP() AS _ingested_at,
  "copia_sql_manual" AS _ingestion_run_id,
  "basedosdados.br_inep_avaliacao_alfabetizacao.uf" AS _source_table
FROM `basedosdados.br_inep_avaliacao_alfabetizacao.uf`;

CREATE OR REPLACE TABLE `SEU_PROJECT_ID.alfabetizacao_bronze.municipio_copia_simples` AS
SELECT
  *,
  CURRENT_TIMESTAMP() AS _ingested_at,
  "copia_sql_manual" AS _ingestion_run_id,
  "basedosdados.br_inep_avaliacao_alfabetizacao.municipio" AS _source_table
FROM `basedosdados.br_inep_avaliacao_alfabetizacao.municipio`;
