# Roteiro do vídeo executivo - até 5 minutos

## 0:00-0:40 - Problema

"O projeto trata do acompanhamento da alfabetização no Brasil. As metas e resultados estão distribuídos por níveis nacional, estadual e municipal, então construí uma pipeline para integrar essas informações e gerar uma visão analítica confiável."

## 0:40-1:40 - Arquitetura

"A solução foi implementada no GCP. O BigQuery recebe a camada Bronze, o Dataform cria Silver e Gold, e o Pub/Sub com Dataflow demonstra o streaming. O Terraform cria a infraestrutura de forma reproduzível."

## 1:40-2:30 - Controle de custo

"Para reduzir custos, a tabela grande de alunos não é carregada integralmente. O código cria uma amostra física de até 500 linhas apenas uma vez e reutiliza essa tabela nas transformações. Também defini limite de bytes por consulta e encerro o Dataflow após a demonstração."

## 2:30-3:30 - Qualidade e resultados

"Na Silver foram implementados limpeza, nulos, tipos, normalização de chaves, duplicidades e integração. Na Gold foram criados indicadores por município e UF, comparação entre meta e resultado, evolução temporal, ranking e uma tabela de features para IA."

## 3:30-4:20 - Streaming e monitoramento

"O publisher envia eventos simulados ao Pub/Sub. O Dataflow valida cada mensagem e separa eventos válidos dos rejeitados. As cargas batch e os testes de qualidade também são registrados em tabelas de monitoramento."

## 4:20-5:00 - Valor e encerramento

"A solução permite acompanhar desigualdades educacionais e pode apoiar dashboards e modelos preditivos. Como o projeto GCP foi criado somente para a apresentação, também preparei um script que cancela os jobs, remove os recursos e solicita a exclusão do projeto inteiro."
