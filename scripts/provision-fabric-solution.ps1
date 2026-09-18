<#
.SYNOPSIS
Creates or reuses the Fabric workspace, Lakehouse, notebooks, and pipelines for the semantic model governance app.

.DESCRIPTION
This script uses Azure CLI interactive authentication and Microsoft Fabric REST APIs.
It does not collect or store Fabric credentials.

The script is idempotent for the core setup path:
- Reuses a workspace when the display name already exists.
- Reuses a Lakehouse when the display name already exists.
- Creates or updates the two solution notebooks.
- Creates or updates sample-load and scan Data Pipelines by default.
- Binds imported notebooks to the Lakehouse through notebook metadata.dependencies.lakehouse.

.EXAMPLE
.\scripts\provision-fabric-solution.ps1 -TenantId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
.\scripts\provision-fabric-solution.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -WorkspaceName "Semantic Model Governance" `
  -LakehouseName "SemanticModelGovernanceLH" `
  -CapacityId "11111111-1111-1111-1111-111111111111"
#>

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$WorkspaceName = "Semantic Model Governance",
    [string]$LakehouseName = "SemanticModelGovernanceLH",
    [string]$ScanNotebookName = "Semantic Model Governance Scan",
    [string]$SampleNotebookName = "Load Sample Governance Data",
    [string]$ScanPipelineName = "Semantic Model Governance - Scan",
    [string]$SamplePipelineName = "Semantic Model Governance - Load Sample Data",
    [string]$ReportName = "Semantic Model Governance Report",
    [string]$CapacityId,
    [string[]]$InitialScanWorkspaceId = @(),
    [string[]]$InitialScanWorkspaceName = @(),
    [switch]$ScanAllAccessibleWorkspaces,
    [switch]$SkipPipelines,
    [switch]$CreateReportShell,
    [string]$ReportSemanticModelId,
    [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"
$FabricApiBase = "https://api.fabric.microsoft.com/v1"
$FabricResource = "https://api.fabric.microsoft.com"
$PowerBiApiBase = "https://api.powerbi.com/v1.0/myorg"
$PowerBiResource = "https://analysis.windows.net/powerbi/api"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Assert-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found on PATH. Install it before running this script."
    }
}

function Invoke-AzLogin {
    if ($SkipLogin) {
        Write-Host "Skipping az login because -SkipLogin was specified."
        return
    }

    $args = @("login", "--allow-no-subscriptions")
    if ($TenantId) {
        $args += @("--tenant", $TenantId)
    }

    Write-Host "Opening Azure CLI sign-in. Complete authentication in the browser or device-code prompt."
    & az @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "az login failed."
    }
}

function Get-FabricAccessToken {
    $token = & az account get-access-token --resource $FabricResource --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not get a Fabric access token from Azure CLI. Run az login and retry."
    }
    return $token.Trim()
}

function Get-PowerBiAccessToken {
    $token = & az account get-access-token --resource $PowerBiResource --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not get a Power BI access token from Azure CLI. Run az login and retry."
    }
    return $token.Trim()
}

function ConvertTo-JsonBody {
    param([Parameter(Mandatory)]$Body)
    return ($Body | ConvertTo-Json -Depth 100 -Compress)
}

function Read-ErrorBody {
    param($ErrorRecord)

    try {
        $response = $ErrorRecord.Exception.Response
        if (-not $response) {
            return $ErrorRecord.Exception.Message
        }

        $stream = $response.GetResponseStream()
        if (-not $stream) {
            return $ErrorRecord.Exception.Message
        }

        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    catch {
        return $ErrorRecord.Exception.Message
    }
}

function Invoke-FabricApi {
    param(
        [Parameter(Mandatory)][ValidateSet("GET", "POST", "PATCH", "PUT", "DELETE")][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        $Body
    )

    $token = Get-FabricAccessToken
    $headers = @{
        Authorization = "Bearer $token"
        Accept = "application/json"
    }

    function Invoke-PowerBiApi {
        param(
            [Parameter(Mandatory)][ValidateSet("GET", "POST", "PATCH", "PUT", "DELETE")][string]$Method,
            [Parameter(Mandatory)][string]$Url,
            $Body
        )

        $token = Get-PowerBiAccessToken
        $headers = @{
            Authorization = "Bearer $token"
            Accept = "application/json"
        }

        $parameters = @{
            Method = $Method
            Uri = $Url
            Headers = $headers
            UseBasicParsing = $true
        }

        if ($PSBoundParameters.ContainsKey("Body")) {
            $parameters["Body"] = ConvertTo-JsonBody $Body
            $parameters["ContentType"] = "application/json"
        }

        try {
            $response = Invoke-WebRequest @parameters
        }
        catch {
            $bodyText = Read-ErrorBody $_
            throw "$Method $Url failed. $bodyText"
        }

        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            return $null
        }

        return $response.Content | ConvertFrom-Json
    }

    $parameters = @{
        Method = $Method
        Uri = $Url
        Headers = $headers
        UseBasicParsing = $true
    }

    if ($PSBoundParameters.ContainsKey("Body")) {
        $parameters["Body"] = ConvertTo-JsonBody $Body
        $parameters["ContentType"] = "application/json"
    }

    try {
        $response = Invoke-WebRequest @parameters
    }
    catch {
        $bodyText = Read-ErrorBody $_
        throw "$Method $Url failed. $bodyText"
    }

    if ([int]$response.StatusCode -eq 202) {
        $location = [string]$response.Headers["Location"]
        $retryAfter = [string]$response.Headers["Retry-After"]
        if ([string]::IsNullOrWhiteSpace($location)) {
            throw "$Method $Url returned 202 Accepted without a Location header."
        }
        return Wait-FabricOperation -Location $location -RetryAfter $retryAfter
    }

    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        return $null
    }

    return $response.Content | ConvertFrom-Json
}

function Wait-FabricOperation {
    param(
        [Parameter(Mandatory)][string]$Location,
        [string]$RetryAfter
    )

    $sleepSeconds = 5
    if (-not [string]::IsNullOrWhiteSpace($RetryAfter)) {
        [void][int]::TryParse($RetryAfter, [ref]$sleepSeconds)
    }

    Write-Host "Long-running Fabric operation started. Polling until it completes..."
    while ($true) {
        Start-Sleep -Seconds $sleepSeconds
        $result = Invoke-FabricApi -Method GET -Url $Location
        $status = [string]$result.status
        if ($status) {
            Write-Host "  status: $status"
        }

        if ($status -eq "Succeeded") {
            return $result
        }

        if ($status -eq "Failed") {
            throw "Fabric long-running operation failed: $($result | ConvertTo-Json -Depth 20 -Compress)"
        }
    }
}

function Get-FabricCollection {
    param([Parameter(Mandatory)][string]$Url)

    $items = New-Object System.Collections.Generic.List[object]
    $nextUrl = $Url
    while (-not [string]::IsNullOrWhiteSpace($nextUrl)) {
        $page = Invoke-FabricApi -Method GET -Url $nextUrl
        if ($page.value) {
            foreach ($item in $page.value) {
                $items.Add($item)
            }
        }

        $nextUrl = $null
        if ($page.continuationUri) {
            $nextUrl = [string]$page.continuationUri
        }
        elseif ($page.PSObject.Properties.Name -contains "@odata.nextLink") {
            $nextUrl = [string]$page."@odata.nextLink"
        }
    }

    return $items
}

function Get-FabricWorkspaceByName {
    param([Parameter(Mandatory)][string]$Name)

    $workspaces = Get-FabricCollection -Url "$FabricApiBase/workspaces"
    return $workspaces | Where-Object { $_.displayName -eq $Name } | Select-Object -First 1
}

function Get-FabricItemByName {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type
    )

    $encodedType = [System.Uri]::EscapeDataString($Type)
    $items = Get-FabricCollection -Url "$FabricApiBase/workspaces/$WorkspaceId/items?type=$encodedType"
    return $items | Where-Object { $_.displayName -eq $Name -and $_.type -eq $Type } | Select-Object -First 1
}

function New-OrGetWorkspace {
    $workspace = Get-FabricWorkspaceByName -Name $WorkspaceName
    if ($workspace) {
        Write-Host "Reusing workspace '$WorkspaceName' ($($workspace.id))."
        return $workspace
    }

    $body = @{ displayName = $WorkspaceName }
    if ($CapacityId) {
        $body.capacityId = $CapacityId
    }

    Write-Host "Creating Fabric workspace '$WorkspaceName'."
    $created = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces" -Body $body
    if ($created -and $created.id) {
        return $created
    }

    $workspace = Get-FabricWorkspaceByName -Name $WorkspaceName
    if (-not $workspace) {
        throw "Workspace '$WorkspaceName' was created asynchronously but could not be found after polling."
    }
    return $workspace
}

function New-OrGetLakehouse {
    param([Parameter(Mandatory)][string]$WorkspaceId)

    $lakehouse = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $LakehouseName -Type "Lakehouse"
    if ($lakehouse) {
        Write-Host "Reusing Lakehouse '$LakehouseName' ($($lakehouse.id))."
        return $lakehouse
    }

    Write-Host "Creating Lakehouse '$LakehouseName'."
    $body = @{
        displayName = $LakehouseName
        type = "Lakehouse"
    }
    $created = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items" -Body $body
    if ($created -and $created.id) {
        return $created
    }

    $lakehouse = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $LakehouseName -Type "Lakehouse"
    if (-not $lakehouse) {
        throw "Lakehouse '$LakehouseName' was created asynchronously but could not be found after polling."
    }
    return $lakehouse
}

function ConvertTo-PythonArrayLiteral {
    param([string[]]$Values)
    if (-not $Values -or $Values.Count -eq 0) {
        return "[]"
    }
    return (,@($Values) | ConvertTo-Json -Compress)
}

function Get-NotebookSource {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [switch]$ApplyScanConfiguration
    )

    $source = Get-Content -Path $SourcePath -Raw
    if ($ApplyScanConfiguration) {
        $scanAll = "False"
        if ($ScanAllAccessibleWorkspaces) {
            $scanAll = "True"
        }

        $source = $source -replace "SCAN_ALL_ACCESSIBLE_WORKSPACES = (True|False)", "SCAN_ALL_ACCESSIBLE_WORKSPACES = $scanAll"
        $source = $source -replace "WORKSPACE_IDS: list\[str\] = \[\]", "WORKSPACE_IDS: list[str] = $(ConvertTo-PythonArrayLiteral -Values $InitialScanWorkspaceId)"
        $source = $source -replace "WORKSPACE_NAMES: list\[str\] = \[\]", "WORKSPACE_NAMES: list[str] = $(ConvertTo-PythonArrayLiteral -Values $InitialScanWorkspaceName)"
    }
    return $source
}

function New-NotebookDefinition {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$LakehouseId,
        [switch]$ApplyScanConfiguration
    )

    $source = Get-NotebookSource -SourcePath $SourcePath -ApplyScanConfiguration:$ApplyScanConfiguration
    $sourceLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($source -split "`r?`n")) {
        $sourceLines.Add("$line`n")
    }

    $notebook = [ordered]@{
        nbformat = 4
        nbformat_minor = 5
        metadata = [ordered]@{
            kernelspec = [ordered]@{
                name = "synapse_pyspark"
                display_name = "Synapse PySpark"
            }
            language_info = [ordered]@{
                name = "python"
            }
            dependencies = [ordered]@{
                lakehouse = [ordered]@{
                    default_lakehouse = $LakehouseId
                    default_lakehouse_workspace_id = $WorkspaceId
                    default_lakehouse_name = $LakehouseName
                }
            }
        }
        cells = @(
            [ordered]@{
                cell_type = "code"
                execution_count = $null
                metadata = @{}
                outputs = @()
                source = $sourceLines
            }
        )
    }

    $json = $notebook | ConvertTo-Json -Depth 100
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    return @{
        format = "ipynb"
        parts = @(
            @{
                path = "notebook-content.ipynb"
                payload = $payload
                payloadType = "InlineBase64"
            }
        )
    }
}

function New-DefinitionFromJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Content
    )

    $json = $Content | ConvertTo-Json -Depth 100
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    return @{
        parts = @(
            @{
                path = $Path
                payload = $payload
                payloadType = "InlineBase64"
            }
        )
    }
}

function New-OrUpdateNotebook {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$LakehouseId,
        [Parameter(Mandatory)][string]$NotebookName,
        [Parameter(Mandatory)][string]$SourcePath,
        [switch]$ApplyScanConfiguration
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Notebook source file not found: $SourcePath"
    }

    $definition = New-NotebookDefinition -SourcePath $SourcePath -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId -ApplyScanConfiguration:$ApplyScanConfiguration
    $existing = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $NotebookName -Type "Notebook"

    if ($existing) {
        Write-Host "Updating Notebook '$NotebookName' ($($existing.id))."
        Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition" -Body @{ definition = $definition } | Out-Null
        return $existing
    }

    Write-Host "Creating Notebook '$NotebookName'."
    $body = @{
        displayName = $NotebookName
        type = "Notebook"
        definition = $definition
    }
    $created = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items" -Body $body
    if ($created -and $created.id) {
        return $created
    }

    $notebook = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $NotebookName -Type "Notebook"
    if (-not $notebook) {
        throw "Notebook '$NotebookName' was created asynchronously but could not be found after polling."
    }
    return $notebook
}

function New-PipelineDefinition {
    param(
        [Parameter(Mandatory)][string]$NotebookId,
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$ActivityName,
        [Parameter(Mandatory)][string]$Description
    )

    $pipeline = [ordered]@{
        properties = [ordered]@{
            description = $Description
            activities = @(
                [ordered]@{
                    name = $ActivityName
                    type = "TridentNotebook"
                    dependsOn = @()
                    policy = [ordered]@{
                        timeout = "0.12:00:00"
                        retry = 1
                        retryIntervalInSeconds = 30
                        secureOutput = $false
                        secureInput = $false
                    }
                    typeProperties = [ordered]@{
                        notebookId = $NotebookId
                        workspaceId = $WorkspaceId
                    }
                }
            )
        }
    }

    return New-DefinitionFromJson -Path "pipeline-content.json" -Content $pipeline
}

function New-OrUpdatePipeline {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$PipelineName,
        [Parameter(Mandatory)][string]$NotebookId,
        [Parameter(Mandatory)][string]$ActivityName,
        [Parameter(Mandatory)][string]$Description
    )

    $definition = New-PipelineDefinition -NotebookId $NotebookId -WorkspaceId $WorkspaceId -ActivityName $ActivityName -Description $Description
    $existing = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $PipelineName -Type "DataPipeline"

    if ($existing) {
        Write-Host "Updating Data Pipeline '$PipelineName' ($($existing.id))."
        Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition" -Body @{ definition = $definition } | Out-Null
        return $existing
    }

    Write-Host "Creating Data Pipeline '$PipelineName'."
    $body = @{
        displayName = $PipelineName
        type = "DataPipeline"
        definition = $definition
    }
    $created = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items" -Body $body
    if ($created -and $created.id) {
        return $created
    }

    $pipeline = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $PipelineName -Type "DataPipeline"
    if (-not $pipeline) {
        throw "Data Pipeline '$PipelineName' was created asynchronously but could not be found after polling."
    }
    return $pipeline
}

function New-OrGetReportShell {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$SemanticModelId
    )

    if ([string]::IsNullOrWhiteSpace($SemanticModelId)) {
        throw "-CreateReportShell requires -ReportSemanticModelId. Create or identify the Power BI semantic model first, then rerun the script with both parameters."
    }

    $reports = Invoke-PowerBiApi -Method GET -Url "$PowerBiApiBase/groups/$WorkspaceId/reports"
    $existing = $reports.value | Where-Object { $_.name -eq $ReportName } | Select-Object -First 1
    if ($existing) {
        Write-Host "Reusing Power BI report '$ReportName' ($($existing.id))."
        return $existing
    }

    Write-Host "Creating blank Power BI report shell '$ReportName' bound to semantic model $SemanticModelId."
    $body = @{
        name = $ReportName
        datasetId = $SemanticModelId
    }
    return Invoke-PowerBiApi -Method POST -Url "$PowerBiApiBase/groups/$WorkspaceId/reports" -Body $body
}

Assert-CommandAvailable -Name "az"
Invoke-AzLogin

$workspace = New-OrGetWorkspace
$lakehouse = New-OrGetLakehouse -WorkspaceId $workspace.id

$sampleNotebookPath = Join-Path $RepoRoot "fabric\notebooks\load_sample_governance_data.py"
$scanNotebookPath = Join-Path $RepoRoot "fabric\notebooks\semantic_model_governance_scan.py"

$sampleNotebook = New-OrUpdateNotebook -WorkspaceId $workspace.id -LakehouseId $lakehouse.id -NotebookName $SampleNotebookName -SourcePath $sampleNotebookPath
$scanNotebook = New-OrUpdateNotebook -WorkspaceId $workspace.id -LakehouseId $lakehouse.id -NotebookName $ScanNotebookName -SourcePath $scanNotebookPath -ApplyScanConfiguration

$samplePipeline = $null
$scanPipeline = $null
if (-not $SkipPipelines) {
    $samplePipeline = New-OrUpdatePipeline `
        -WorkspaceId $workspace.id `
        -PipelineName $SamplePipelineName `
        -NotebookId $sampleNotebook.id `
        -ActivityName "Load sample governance data" `
        -Description "Loads synthetic sample governance data into the solution Lakehouse for report validation."

    $scanPipeline = New-OrUpdatePipeline `
        -WorkspaceId $workspace.id `
        -PipelineName $ScanPipelineName `
        -NotebookId $scanNotebook.id `
        -ActivityName "Run semantic model governance scan" `
        -Description "Runs the semantic model duplicate governance scan and writes results to the solution Lakehouse."
}

$reportShell = $null
if ($CreateReportShell) {
    $reportShell = New-OrGetReportShell -WorkspaceId $workspace.id -SemanticModelId $ReportSemanticModelId
}

$summary = [ordered]@{
    workspaceName = $WorkspaceName
    workspaceId = $workspace.id
    lakehouseName = $LakehouseName
    lakehouseId = $lakehouse.id
    sampleNotebookName = $SampleNotebookName
    sampleNotebookId = $sampleNotebook.id
    scanNotebookName = $ScanNotebookName
    scanNotebookId = $scanNotebook.id
    samplePipelineName = if ($samplePipeline) { $SamplePipelineName } else { $null }
    samplePipelineId = if ($samplePipeline) { $samplePipeline.id } else { $null }
    scanPipelineName = if ($scanPipeline) { $ScanPipelineName } else { $null }
    scanPipelineId = if ($scanPipeline) { $scanPipeline.id } else { $null }
    reportName = if ($reportShell) { $ReportName } else { $null }
    reportId = if ($reportShell) { $reportShell.id } else { $null }
    nextSteps = @(
        "Open the Fabric workspace and confirm the Lakehouse, notebooks, and Data Pipelines are present.",
        "Attach or create a Fabric Environment that installs this package if your workspace does not support inline package install.",
        "Trigger the sample-load pipeline first, then build or connect the Power BI report from the Lakehouse tables.",
        "Configure scan scope, trigger the scan pipeline, then schedule it through Fabric."
    )
}

Write-Host ""
Write-Host "Provisioning complete."
$summary | ConvertTo-Json -Depth 10
