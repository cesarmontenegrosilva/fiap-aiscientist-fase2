<#
.SYNOPSIS
  Encerra os jobs, remove os recursos do Tech Challenge e pode excluir o projeto GCP.

.DESCRIPTION
  Este script foi feito para um projeto temporário criado somente para a demonstração.
  Use -DryRun primeiro. Use -DeleteProject somente quando nenhum outro sistema utilizar
  o projeto informado. O projeto público "basedosdados" é bloqueado pelo código.

.EXAMPLE
  # Simular a exclusão completa, inclusive do projeto.
  .\scripts\limpar_gcp.ps1 `
    -ProjectId meu-projeto `
    -Bucket meu-projeto-alfabetizacao-lake `
    -DeleteProject `
    -DryRun

.EXAMPLE
  # Executar a exclusão completa, inclusive do projeto.
  .\scripts\limpar_gcp.ps1 `
    -ProjectId meu-projeto `
    -Bucket meu-projeto-alfabetizacao-lake `
    -DeleteProject
#>

# Declara os parâmetros aceitos pelo script.
[CmdletBinding()]
param(
    # ID exato do projeto temporário que será limpo.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')]
    [string]$ProjectId,

    # Região onde Dataflow, Cloud Run e Scheduler foram criados.
    [string]$Region = "us-central1",

    # Nome do bucket criado para o projeto.
    [string]$Bucket = "",

    # Evita terraform destroy mesmo quando há state local.
    [switch]$SkipTerraform,

    # Desativa as APIs depois de remover os recursos.
    [switch]$DisableApis,

    # Desvincula a conta de faturamento quando o projeto for mantido.
    [switch]$UnlinkBilling,

    # Solicita também a exclusão do projeto GCP inteiro.
    [switch]$DeleteProject,

    # Apenas mostra os comandos, sem alterar o GCP.
    [switch]$DryRun,

    # Pula a confirmação interativa; use apenas em automação controlada.
    [switch]$Yes
)

# Ativa regras mais rigorosas do PowerShell.
Set-StrictMode -Version Latest
# Faz o script parar quando um cmdlet PowerShell falhar.
$ErrorActionPreference = "Stop"

# Impede a exclusão acidental do projeto público usado como origem.
if ($ProjectId -eq "basedosdados") {
    throw "Operação bloqueada: basedosdados é a origem pública e nunca deve ser apagada."
}

# Localiza a raiz do repositório a partir da pasta scripts.
$RepoRoot = Split-Path -Parent $PSScriptRoot
# Localiza a pasta Terraform.
$TerraformDir = Join-Path $RepoRoot "terraform"
# Localiza o state local do Terraform.
$TerraformState = Join-Path $TerraformDir "terraform.tfstate"

# Define os datasets criados pelo projeto.
$Datasets = @(
    "alfabetizacao_bronze",
    "alfabetizacao_silver",
    "alfabetizacao_gold",
    "alfabetizacao_monitoring",
    "alfabetizacao_assertions"
)

# Define as APIs que podem ser desativadas no final.
$ProjectApis = @(
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "compute.googleapis.com",
    "dataflow.googleapis.com",
    "dataform.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com"
)

function Write-Section {
    # Recebe o título de uma etapa.
    param([string]$Title)
    # Cria uma linha em branco para melhorar a leitura.
    Write-Host ""
    # Imprime o separador superior.
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    # Imprime o título da etapa.
    Write-Host $Title -ForegroundColor Cyan
    # Imprime o separador inferior.
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}

function Assert-Command {
    # Recebe o nome de um comando obrigatório.
    param([string]$Name)
    # Verifica se o executável está no PATH.
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        # Interrompe com orientação simples quando o comando não está instalado.
        throw "Comando '$Name' não encontrado. Instale-o e reabra o VS Code."
    }
}

function Invoke-External {
    # Declara os parâmetros da função que executa comandos externos.
    param(
        # Nome do executável.
        [Parameter(Mandatory = $true)][string]$Command,
        # Lista de argumentos do executável.
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        # Permite continuar quando o recurso já não existe.
        [switch]$IgnoreErrors,
        # Devolve a saída para processamento pelo script.
        [switch]$CaptureOutput
    )

    # Constrói uma versão legível do comando para exibir no terminal.
    $displayArguments = $Arguments | ForEach-Object {
        # Coloca aspas em argumentos que possuem espaços.
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }
    # Mostra exatamente qual comando seria ou será executado.
    Write-Host "+ $Command $($displayArguments -join ' ')" -ForegroundColor DarkGray

    # No modo DryRun, nenhum executável externo é chamado.
    if ($DryRun) {
        # Devolve uma lista vazia quando a função deveria capturar saída.
        if ($CaptureOutput) { return @() }
        # Sai da função sem alterar o GCP.
        return
    }

    # A captura de saída é usada nas operações de listagem.
    if ($CaptureOutput) {
        # Executa o comando e descarta mensagens de erro esperadas.
        $output = & $Command @Arguments 2>$null
        # Guarda o código devolvido pelo executável.
        $exitCode = $LASTEXITCODE
        # Interrompe apenas quando a falha não foi marcada como tolerável.
        if ($exitCode -ne 0 -and -not $IgnoreErrors) {
            throw "Falha ao executar '$Command'. Código: $exitCode"
        }
        # Remove linhas vazias antes de devolver o resultado.
        return @($output | Where-Object { $_ -and $_.Trim() -ne "" })
    }

    # Executa comandos que não precisam devolver dados ao script.
    & $Command @Arguments
    # Guarda o código de saída.
    $exitCode = $LASTEXITCODE
    # Interrompe quando uma falha obrigatória ocorrer.
    if ($exitCode -ne 0 -and -not $IgnoreErrors) {
        throw "Falha ao executar '$Command'. Código: $exitCode"
    }
}

function Remove-SchedulerJobs {
    # Mostra a etapa atual.
    Write-Section "1/9 - Removendo agendamentos do Cloud Scheduler"
    # Lista agendamentos cujo nome contém alfabetizacao.
    $jobs = @(Invoke-External -Command "gcloud" -CaptureOutput -IgnoreErrors -Arguments @(
        "scheduler", "jobs", "list",
        "--project=$ProjectId",
        "--location=$Region",
        "--filter=name~alfabetizacao",
        "--format=value(name)"
    ))
    # Percorre cada agendamento encontrado.
    foreach ($fullName in $jobs) {
        # Extrai somente o nome curto do recurso.
        $jobName = ($fullName -split "/")[-1]
        # Exclui o agendamento para impedir novas execuções.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
            "scheduler", "jobs", "delete", $jobName,
            "--project=$ProjectId",
            "--location=$Region",
            "--quiet"
        )
    }
}

function Stop-DataflowJobs {
    # Mostra a etapa atual.
    Write-Section "2/9 - Cancelando jobs ativos do Dataflow"
    # Lista jobs ativos do projeto relacionados à alfabetização.
    $jobs = @(Invoke-External -Command "gcloud" -CaptureOutput -IgnoreErrors -Arguments @(
        "dataflow", "jobs", "list",
        "--project=$ProjectId",
        "--region=$Region",
        "--status=active",
        "--filter=name~alfabetizacao",
        "--format=value(id)"
    ))
    # Percorre cada job encontrado.
    foreach ($jobId in $jobs) {
        # Cancela o job para interromper cobrança de workers.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
            "dataflow", "jobs", "cancel", $jobId,
            "--project=$ProjectId",
            "--region=$Region",
            "--quiet"
        )
    }
}

function Remove-CloudRunResources {
    # Mostra a etapa atual.
    Write-Section "3/9 - Cancelando e removendo recursos do Cloud Run"
    # Lista execuções do job batch.
    $executions = @(Invoke-External -Command "gcloud" -CaptureOutput -IgnoreErrors -Arguments @(
        "run", "jobs", "executions", "list",
        "--job=alfabetizacao-batch",
        "--project=$ProjectId",
        "--region=$Region",
        "--format=value(metadata.name)"
    ))
    # Percorre execuções ainda visíveis no serviço.
    foreach ($execution in $executions) {
        # Solicita cancelamento; execuções finalizadas são ignoradas.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
            "run", "jobs", "executions", "cancel", $execution,
            "--project=$ProjectId",
            "--region=$Region",
            "--quiet"
        )
    }
    # Exclui o job batch, caso exista.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "run", "jobs", "delete", "alfabetizacao-batch",
        "--project=$ProjectId",
        "--region=$Region",
        "--quiet"
    )
}

function Invoke-TerraformDestroy {
    # Mostra a etapa atual.
    Write-Section "4/9 - Executando terraform destroy quando houver state local"
    # Sai quando o usuário pediu para ignorar o Terraform.
    if ($SkipTerraform) {
        Write-Host "Terraform ignorado pelo parâmetro -SkipTerraform."
        return
    }
    # Sai quando a infraestrutura não possui state local.
    if (-not (Test-Path $TerraformState)) {
        Write-Host "Nenhum terraform.tfstate local encontrado."
        return
    }
    # Sai quando o executável não está instalado.
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Warning "Terraform não encontrado; a limpeza manual continuará."
        return
    }
    # O nome do bucket é necessário para reproduzir as variáveis do state.
    if ([string]::IsNullOrWhiteSpace($Bucket)) {
        Write-Warning "Bucket não informado; a limpeza manual continuará."
        return
    }
    # Executa a destruição dos recursos controlados pelo Terraform.
    Invoke-External -Command "terraform" -IgnoreErrors -Arguments @(
        "-chdir=$TerraformDir",
        "destroy",
        "-auto-approve",
        "-var=project_id=$ProjectId",
        "-var=region=$Region",
        "-var=bigquery_location=US",
        "-var=bucket_name=$Bucket",
        "-var=allow_destroy_data=true"
    )
}

function Remove-PubSubResources {
    # Mostra a etapa atual.
    Write-Section "5/9 - Removendo tópico e assinatura Pub/Sub"
    # Exclui primeiro a assinatura que depende do tópico.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "pubsub", "subscriptions", "delete", "alfabetizacao-indicadores-dataflow",
        "--project=$ProjectId",
        "--quiet"
    )
    # Exclui o tópico depois da assinatura.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "pubsub", "topics", "delete", "alfabetizacao-indicadores",
        "--project=$ProjectId",
        "--quiet"
    )
}

function Remove-BigQueryDatasets {
    # Mostra a etapa atual.
    Write-Section "6/9 - Removendo datasets e tabelas do BigQuery"
    # Percorre todos os datasets criados pela aplicação.
    foreach ($dataset in $Datasets) {
        # --recursive remove também as tabelas internas.
        Invoke-External -Command "bq" -IgnoreErrors -Arguments @(
            "rm",
            "--recursive=true",
            "--force=true",
            "--dataset=true",
            "$ProjectId`:$dataset"
        )
    }
}

function Remove-StorageResources {
    # Mostra a etapa atual.
    Write-Section "7/9 - Removendo objetos, versões e bucket do Cloud Storage"
    # Sem nome de bucket não é seguro tentar descobrir e apagar automaticamente.
    if ([string]::IsNullOrWhiteSpace($Bucket)) {
        Write-Warning "Bucket não informado; use -Bucket NOME_DO_BUCKET."
        return
    }
    # Remove objetos atuais e versões anteriores; falhas por bucket vazio são toleradas.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "storage", "rm",
        "--recursive",
        "--all-versions",
        "gs://$Bucket/**"
    )
    # Exclui o próprio bucket depois de esvaziá-lo.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "storage", "buckets", "delete", "gs://$Bucket",
        "--quiet"
    )
}

function Remove-AuxiliaryResources {
    # Mostra a etapa atual.
    Write-Section "8/9 - Removendo Artifact Registry e contas de serviço"
    # Exclui o repositório de imagens Docker.
    Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
        "artifacts", "repositories", "delete", "alfabetizacao-pipelines",
        "--project=$ProjectId",
        "--location=$Region",
        "--quiet"
    )
    # Percorre as contas de serviço criadas pelo Terraform.
    foreach ($account in @("alfabetizacao-batch", "alfabetizacao-dataflow")) {
        # Exclui cada conta de serviço.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
            "iam", "service-accounts", "delete",
            "$account@$ProjectId.iam.gserviceaccount.com",
            "--project=$ProjectId",
            "--quiet"
        )
    }
}

function Finish-Project {
    # Mostra a etapa atual.
    Write-Section "9/9 - Finalizando projeto, APIs e faturamento"
    # Desativa APIs somente quando o parâmetro foi informado.
    if ($DisableApis) {
        # Monta a lista completa de argumentos para o comando.
        $arguments = @("services", "disable") + $ProjectApis + @(
            "--project=$ProjectId",
            "--force",
            "--quiet"
        )
        # Desativa as APIs do projeto.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments $arguments
    }
    # Desvincula o faturamento somente quando solicitado.
    if ($UnlinkBilling) {
        # Executa a desvinculação do projeto.
        Invoke-External -Command "gcloud" -IgnoreErrors -Arguments @(
            "billing", "projects", "unlink", $ProjectId,
            "--quiet"
        )
    }
    # A exclusão do projeto remove qualquer recurso restante após o período do GCP.
    if ($DeleteProject) {
        # Solicita a exclusão do projeto temporário.
        Invoke-External -Command "gcloud" -Arguments @(
            "projects", "delete", $ProjectId,
            "--quiet"
        )
    }
}

# Confirma que o Google Cloud CLI está disponível.
Assert-Command "gcloud"
# Confirma que a ferramenta bq está disponível.
Assert-Command "bq"

# Exibe um resumo antes de qualquer ação.
Write-Host "Projeto alvo : $ProjectId" -ForegroundColor Yellow
# Exibe a região usada para os recursos regionais.
Write-Host "Região      : $Region" -ForegroundColor Yellow
# Exibe o bucket que será removido.
Write-Host "Bucket      : $(if ($Bucket) { $Bucket } else { '<não informado>' })" -ForegroundColor Yellow
# Exibe se o projeto também será excluído.
Write-Host "Excluir proj.: $DeleteProject" -ForegroundColor Yellow
# Exibe se a execução é apenas uma simulação.
Write-Host "Dry run     : $DryRun" -ForegroundColor Yellow

# Solicita confirmação em toda execução destrutiva que não usar -Yes.
if (-not $DryRun -and -not $Yes) {
    # Usa uma frase mais forte quando o projeto inteiro será excluído.
    $expected = if ($DeleteProject) {
        "EXCLUIR PROJETO $ProjectId"
    } else {
        "APAGAR RECURSOS $ProjectId"
    }
    # Mostra o aviso de irreversibilidade.
    Write-Host "ATENÇÃO: esta operação é destrutiva." -ForegroundColor Red
    # Lê a confirmação digitada pelo usuário.
    $confirmation = Read-Host "Digite exatamente '$expected' para continuar"
    # Interrompe sem alterar o GCP quando a frase estiver incorreta.
    if ($confirmation -ne $expected) {
        throw "Confirmação incorreta. Nenhum recurso foi removido."
    }
}

# Remove o agendamento antes de qualquer outra etapa.
Remove-SchedulerJobs
# Cancela o streaming para interromper custos computacionais.
Stop-DataflowJobs
# Cancela e remove o job batch.
Remove-CloudRunResources
# Tenta remover primeiro os recursos controlados pelo Terraform.
Invoke-TerraformDestroy
# Executa limpeza manual idempotente para recursos restantes.
Remove-PubSubResources
# Remove as tabelas e datasets.
Remove-BigQueryDatasets
# Remove Parquet, temporários, versões e o bucket.
Remove-StorageResources
# Remove imagens e identidades de serviço.
Remove-AuxiliaryResources
# Desativa APIs, desvincula billing ou exclui o projeto conforme parâmetros.
Finish-Project

# Cria uma linha em branco antes do resultado final.
Write-Host ""
# Informa que nada foi modificado no modo simulado.
if ($DryRun) {
    Write-Host "Simulação concluída. Nenhum recurso foi alterado." -ForegroundColor Green
# Informa o resultado específico quando o projeto foi excluído.
} elseif ($DeleteProject) {
    Write-Host "Projeto marcado para exclusão pelo Google Cloud." -ForegroundColor Green
    Write-Host "Verifique com:" -ForegroundColor Cyan
    Write-Host "gcloud projects list --filter='projectId=$ProjectId lifecycleState:DELETE_REQUESTED'" -ForegroundColor DarkGray
# Informa o resultado quando apenas os recursos foram removidos.
} else {
    Write-Host "Limpeza dos recursos concluída; o projeto foi mantido." -ForegroundColor Green
    Write-Host "Para excluir também o projeto, execute novamente com -DeleteProject." -ForegroundColor Yellow
}
