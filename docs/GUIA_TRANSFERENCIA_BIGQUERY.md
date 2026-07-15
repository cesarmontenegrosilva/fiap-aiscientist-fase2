# Como os dados são transferidos

O comando principal é:

```powershell
python scripts\transferir_dados_inep.py --project-id SEU_PROJECT_ID --sem-parquet
```

O script usa credenciais locais do Google Cloud, cria Bronze e Monitoring quando necessário e consulta as tabelas públicas da Base dos Dados.

As tabelas pequenas são adicionadas como snapshots. Para alunos, a configuração é diferente:

```yaml
name: alunos_amostra
source_table: alunos
destination_table: alunos_amostra
mode: physical_sample_once
sample_rows: 500
sample_percent: 1
```

Na primeira execução, o BigQuery cria uma tabela física local. Nas próximas execuções, o código verifica que ela já existe e não consulta novamente a tabela pública de alunos.

Para recriar conscientemente:

```powershell
python scripts\transferir_dados_inep.py --project-id SEU_PROJECT_ID --sem-parquet --recriar-amostra
```
