-- TROQUE PROJECT_ID pelo ID real antes de executar.
-- Seleciona campos que podem alimentar um mapa municipal no Looker Studio.
SELECT
  id_municipio,
  nome_municipio,
  sigla_uf,
  regiao,
  taxa_alfabetizacao,
  meta_alfabetizacao,
  gap_meta_pontos_percentuais,
  status_meta
-- Usa a tabela Gold com o resultado mais recente.
FROM `PROJECT_ID.alfabetizacao_gold.situacao_atual_municipio`
-- Exclui linhas sem indicador calculado.
WHERE taxa_alfabetizacao IS NOT NULL;
