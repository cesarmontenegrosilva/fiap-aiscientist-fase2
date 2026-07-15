# Runbook de operação

## Batch falhou

1. confira `alfabetizacao_monitoring.pipeline_runs`;
2. leia `error_message`;
3. confirme autenticação com `gcloud auth application-default login`;
4. confirme `GCP_PROJECT_ID` no `.env`;
5. reduza a seleção com `--tables` para identificar a fonte com erro.

## Dataform falhou

1. execute `bash scripts/run_dataform.sh`;
2. leia o nome do modelo ou assertion com erro;
3. confirme que a Bronze foi criada;
4. confirme `defaultProject` em `dataform/workflow_settings.yaml`.

## Dataflow não processa mensagens

1. verifique se o job está ativo;
2. confira a assinatura Pub/Sub;
3. verifique a conta de serviço;
4. consulte `eventos_rejeitados`;
5. encerre o job com `bash scripts/stop_dataflow.sh` quando terminar.

## Custo inesperado

1. pare Dataflow imediatamente;
2. não use `--recriar-amostra` sem necessidade;
3. use `--sem-parquet` durante testes;
4. execute o script de limpeza em `-DryRun` e depois faça a exclusão real.
