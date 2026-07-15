-- TROQUE PROJECT_ID pelo ID real antes de executar.
-- Agrega a evolução anual média por unidade federativa.
SELECT
  ano,
  sigla_uf,
  -- Calcula a média do indicador no recorte.
  AVG(taxa_alfabetizacao) AS taxa_media,
  -- Conta quantos municípios participam do cálculo.
  COUNT(DISTINCT id_municipio) AS municipios
-- Lê a tabela temporal da Gold.
FROM `PROJECT_ID.alfabetizacao_gold.evolucao_temporal`
-- Agrupa por ano e UF.
GROUP BY 1, 2
-- Mantém a série em ordem cronológica e alfabética.
ORDER BY 1, 2;
