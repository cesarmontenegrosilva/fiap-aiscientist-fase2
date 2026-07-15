# Limpeza e exclusão do projeto

Primeiro simule:

```powershell
.\scripts\limpar_gcp.ps1 `
  -ProjectId SEU_PROJECT_ID `
  -Bucket SEU_PROJECT_ID-alfabetizacao-lake `
  -DeleteProject `
  -DryRun
```

Depois execute:

```powershell
.\scripts\limpar_gcp.ps1 `
  -ProjectId SEU_PROJECT_ID `
  -Bucket SEU_PROJECT_ID-alfabetizacao-lake `
  -DeleteProject
```

A frase de confirmação é:

```text
EXCLUIR PROJETO SEU_PROJECT_ID
```

O script cancela Dataflow antes de excluir dados. O projeto `basedosdados` está bloqueado. Use `-DeleteProject` somente porque este projeto foi criado exclusivamente para o evento.
