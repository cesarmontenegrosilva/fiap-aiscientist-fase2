-- TROQUE PROJECT_ID pelo ID real antes de executar.
-- Conta municípios e resume os principais resultados da visão atual.
SELECT
  -- Quantidade de municípios presentes na tabela Gold.
  COUNT(DISTINCT id_municipio) AS municipios_monitorados,
  -- Média simples do indicador municipal.
  ROUND(AVG(taxa_alfabetizacao), 2) AS taxa_media_alfabetizacao,
  -- Municípios que atingiram ou superaram a meta.
  COUNTIF(status_meta = 'META_ATINGIDA') AS municipios_meta_atingida,
  -- Municípios que ficaram abaixo da meta.
  COUNTIF(status_meta = 'ABAIXO_DA_META') AS municipios_abaixo_meta,
  -- Diferença média entre resultado e meta.
  ROUND(AVG(gap_meta_pontos_percentuais), 2) AS gap_medio_meta
-- Lê a visão municipal mais recente da Gold.
FROM `PROJECT_ID.alfabetizacao_gold.situacao_atual_municipio`;
