-- TROQUE PROJECT_ID pelo ID real antes de executar.
-- Mostra a classificação nacional e estadual dos municípios.
SELECT
  ranking_brasil,
  ranking_uf,
  nome_municipio,
  sigla_uf,
  taxa_alfabetizacao,
  meta_alfabetizacao,
  status_meta
-- Lê o ranking materializado na Gold.
FROM `PROJECT_ID.alfabetizacao_gold.ranking_municipios`
-- Ordena do melhor para o menor resultado.
ORDER BY ranking_brasil;
