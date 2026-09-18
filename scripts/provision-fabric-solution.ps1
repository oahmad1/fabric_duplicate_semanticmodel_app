<#
.SYNOPSIS
Creates or reuses the Fabric workspace, Lakehouse, notebooks, pipelines, governance semantic model, and optional template report clone for the semantic model governance app.

.DESCRIPTION
This script uses Azure CLI interactive authentication and Microsoft Fabric REST APIs.
It does not collect or store Fabric credentials.

The script is idempotent for the core setup path:
- Reuses a workspace when the display name already exists.
- Reuses a Lakehouse when the display name already exists.
- Creates or updates the solution notebooks.
- Creates or updates sample-load and scan Data Pipelines by default.
- Creates or updates a Direct Lake semantic model over the standardized governance tables by default.
- Can clone and rebind a Power BI template report when a template report ID is supplied.
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
    [string]$InitializeNotebookName = "Initialize Governance Tables",
    [string]$ScanNotebookName = "Semantic Model Governance Scan",
    [string]$SampleNotebookName = "Load Sample Governance Data",
    [string]$InitializePipelineName = "Semantic Model Governance - Initialize Tables",
    [string]$ScanPipelineName = "Semantic Model Governance - Scan",
    [string]$SamplePipelineName = "Semantic Model Governance - Load Sample Data",
    [string]$SemanticModelName = "Semantic Model Governance Semantic Model",
    [string]$ReportName = "Semantic Model Governance Report",
    [string]$TemplateReportId,
    [string]$TemplateReportWorkspaceId,
    [string]$CapacityId,
    [string[]]$InitialScanWorkspaceId = @(),
    [string[]]$InitialScanWorkspaceName = @(),
    [switch]$ScanAllAccessibleWorkspaces,
    [switch]$SkipPipelines,
    [switch]$SkipInitializationRun,
    [switch]$SkipSemanticModel,
    [switch]$SkipReport,
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

function New-TextDefinitionPart {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    return @{
        path = $Path
        payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
        payloadType = "InlineBase64"
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

function Wait-FabricItemJob {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$JobInstanceId,
        [int]$TimeoutMinutes = 60
    )

    Write-Host "Waiting for job instance $JobInstanceId to complete..."
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        $job = Invoke-FabricApi -Method GET -Url "$FabricApiBase/workspaces/$WorkspaceId/items/$ItemId/jobs/instances/$JobInstanceId"
        $status = [string]$job.status
        if ([string]::IsNullOrWhiteSpace($status)) {
            $status = [string]$job.state
        }
        if ($status) {
            Write-Host "  job status: $status"
        }

        if ($status -in @("Completed", "Succeeded", "Success")) {
            return $job
        }

        if ($status -in @("Failed", "Cancelled", "Canceled")) {
            throw "Fabric job $JobInstanceId failed: $($job | ConvertTo-Json -Depth 20 -Compress)"
        }
    }

    throw "Fabric job $JobInstanceId did not complete within $TimeoutMinutes minutes."
}

function Start-FabricNotebookRun {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$NotebookId,
        [Parameter(Mandatory)][string]$LakehouseId,
        [Parameter(Mandatory)][string]$LakehouseNameForRun
    )

    $body = @{
        executionData = @{
            configuration = @{
                defaultLakehouse = @{
                    id = $LakehouseId
                    name = $LakehouseNameForRun
                }
                useStarterPool = $true
            }
        }
    }

    Write-Host "Starting notebook job for item $NotebookId."
    $job = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/items/$NotebookId/jobs/instances?jobType=RunNotebook" -Body $body
    $jobId = [string]$job.id
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        $jobId = [string]$job.jobInstanceId
    }
    if ($jobId) {
        return Wait-FabricItemJob -WorkspaceId $WorkspaceId -ItemId $NotebookId -JobInstanceId $jobId
    }

    Write-Host "Notebook run was accepted, but no job instance ID was returned. Waiting briefly before continuing."
    Start-Sleep -Seconds 30
    return $job
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

function Get-GovernanceModelTables {
    return @(
        @{
            name = "semantic_model_scan_runs"
            keyColumns = @("run_id")
            hiddenColumns = @()
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "started_at_utc"; type = "string" },
                @{ name = "completed_at_utc"; type = "string" },
                @{ name = "scan_status"; type = "string" },
                @{ name = "workspace_count"; type = "int64" },
                @{ name = "model_count"; type = "int64" },
                @{ name = "finding_count"; type = "int64" },
                @{ name = "warning_count"; type = "int64" }
            )
            measures = @(
                @{ name = "Scan Runs"; expression = "DISTINCTCOUNT(semantic_model_scan_runs[run_id])"; format = "#,##0" },
                @{ name = "Completed Scan Runs"; expression = "CALCULATE([Scan Runs], semantic_model_scan_runs[scan_status] = `"completed`")"; format = "#,##0" },
                @{ name = "Latest Model Count"; expression = "MAX(semantic_model_scan_runs[model_count])"; format = "#,##0" },
                @{ name = "Latest Finding Count"; expression = "MAX(semantic_model_scan_runs[finding_count])"; format = "#,##0" }
            )
        },
        @{
            name = "semantic_model_inventory"
            keyColumns = @()
            hiddenColumns = @("run_id", "workspace_id", "model_id")
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "workspace_id"; type = "string" },
                @{ name = "workspace_name"; type = "string" },
                @{ name = "model_id"; type = "string" },
                @{ name = "model_name"; type = "string" },
                @{ name = "table_count"; type = "int64" },
                @{ name = "column_count"; type = "int64" },
                @{ name = "measure_count"; type = "int64" },
                @{ name = "relationship_count"; type = "int64" },
                @{ name = "data_source_count"; type = "int64" },
                @{ name = "warning_count"; type = "int64" }
            )
            measures = @(
                @{ name = "Models Scanned"; expression = "DISTINCTCOUNT(semantic_model_inventory[model_id])"; format = "#,##0" },
                @{ name = "Workspaces Scanned"; expression = "DISTINCTCOUNT(semantic_model_inventory[workspace_id])"; format = "#,##0" }
            )
        },
        @{
            name = "semantic_model_objects"
            keyColumns = @()
            hiddenColumns = @("run_id", "workspace_id", "model_id")
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "workspace_id"; type = "string" },
                @{ name = "workspace_name"; type = "string" },
                @{ name = "model_id"; type = "string" },
                @{ name = "model_name"; type = "string" },
                @{ name = "object_type"; type = "string" },
                @{ name = "object_name"; type = "string" }
            )
            measures = @(
                @{ name = "Model Object Count"; expression = "COUNTROWS(semantic_model_objects)"; format = "#,##0" }
            )
        },
        @{
            name = "semantic_model_findings"
            keyColumns = @("finding_id")
            hiddenColumns = @("run_id", "finding_id", "left_workspace_id", "left_model_id", "right_workspace_id", "right_model_id")
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "finding_id"; type = "string" },
                @{ name = "classification"; type = "string" },
                @{ name = "confidence"; type = "string" },
                @{ name = "duplicate_score"; type = "double" },
                @{ name = "overlap_score"; type = "double" },
                @{ name = "left_workspace_id"; type = "string" },
                @{ name = "left_workspace_name"; type = "string" },
                @{ name = "left_model_id"; type = "string" },
                @{ name = "left_model_name"; type = "string" },
                @{ name = "right_workspace_id"; type = "string" },
                @{ name = "right_workspace_name"; type = "string" },
                @{ name = "right_model_id"; type = "string" },
                @{ name = "right_model_name"; type = "string" },
                @{ name = "shared_tables"; type = "int64" },
                @{ name = "shared_columns"; type = "int64" },
                @{ name = "shared_measures"; type = "int64" },
                @{ name = "shared_relationships"; type = "int64" },
                @{ name = "shared_data_sources"; type = "int64" },
                @{ name = "warnings"; type = "string" }
            )
            measures = @(
                @{ name = "Finding Count"; expression = "COUNTROWS(semantic_model_findings)"; format = "#,##0" },
                @{ name = "Likely Duplicate Count"; expression = "CALCULATE([Finding Count], semantic_model_findings[classification] = `"likely_duplicate`")"; format = "#,##0" },
                @{ name = "High Overlap Count"; expression = "CALCULATE([Finding Count], semantic_model_findings[classification] = `"high_overlap`")"; format = "#,##0" },
                @{ name = "Average Duplicate Score"; expression = "AVERAGE(semantic_model_findings[duplicate_score])"; format = "0.00%" },
                @{ name = "Average Overlap Score"; expression = "AVERAGE(semantic_model_findings[overlap_score])"; format = "0.00%" },
                @{ name = "Max Duplicate Score"; expression = "MAX(semantic_model_findings[duplicate_score])"; format = "0.00%" },
                @{ name = "High Confidence Findings"; expression = "CALCULATE([Finding Count], semantic_model_findings[confidence] = `"high`")"; format = "#,##0" }
            )
        },
        @{
            name = "semantic_model_common_objects"
            keyColumns = @()
            hiddenColumns = @("run_id", "finding_id")
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "finding_id"; type = "string" },
                @{ name = "object_type"; type = "string" },
                @{ name = "object_name"; type = "string" }
            )
            measures = @(
                @{ name = "Common Object Count"; expression = "COUNTROWS(semantic_model_common_objects)"; format = "#,##0" }
            )
        },
        @{
            name = "semantic_model_warnings"
            keyColumns = @()
            hiddenColumns = @("run_id", "workspace_id", "model_id")
            columns = @(
                @{ name = "run_id"; type = "string" },
                @{ name = "workspace_id"; type = "string" },
                @{ name = "workspace_name"; type = "string" },
                @{ name = "model_id"; type = "string" },
                @{ name = "model_name"; type = "string" },
                @{ name = "stage"; type = "string" },
                @{ name = "message"; type = "string" }
            )
            measures = @(
                @{ name = "Warning Count"; expression = "COUNTROWS(semantic_model_warnings)"; format = "#,##0" }
            )
        }
    )
}

function New-GovernanceTableTmdl {
    param([Parameter(Mandatory)]$Table)

    $lines = New-Object System.Collections.Generic.List[string]
    $tableName = [string]$Table.name
    $lines.Add("table $tableName")
    $lines.Add("")

    foreach ($measure in $Table.measures) {
        $lines.Add("`tmeasure '$($measure.name)' = $($measure.expression)")
        $lines.Add("`t`tformatString: $($measure.format)")
        $lines.Add("")
    }

    foreach ($column in $Table.columns) {
        $columnName = [string]$column.name
        $lines.Add("`tcolumn $columnName")
        $lines.Add("`t`tdataType: $($column.type)")
        if ($Table.hiddenColumns -contains $columnName) {
            $lines.Add("`t`tisHidden")
        }
        if ($Table.keyColumns -contains $columnName) {
            $lines.Add("`t`tisKey")
        }
        if ($column.type -in @("int64", "double", "decimal")) {
            $lines.Add("`t`tsummarizeBy: none")
        }
        $lines.Add("`t`tsourceColumn: $columnName")
        $lines.Add("")
    }

    $lines.Add("`tpartition $tableName = entity")
    $lines.Add("`t`tmode: directLake")
    $lines.Add("`t`tsource")
    $lines.Add("`t`t`tentityName: $tableName")
    $lines.Add("`t`t`tschemaName: dbo")
    $lines.Add("`t`t`texpressionSource: DL_Lakehouse")
    return ($lines -join "`n")
}

function New-GovernanceRelationshipsTmdl {
    $lines = @(
        "relationship scan_runs_to_inventory",
        "`tfromColumn: semantic_model_inventory.run_id",
        "`ttoColumn: semantic_model_scan_runs.run_id",
        "",
        "relationship scan_runs_to_findings",
        "`tfromColumn: semantic_model_findings.run_id",
        "`ttoColumn: semantic_model_scan_runs.run_id",
        "",
        "relationship scan_runs_to_warnings",
        "`tfromColumn: semantic_model_warnings.run_id",
        "`ttoColumn: semantic_model_scan_runs.run_id",
        "",
        "relationship findings_to_common_objects",
        "`tfromColumn: semantic_model_common_objects.finding_id",
        "`ttoColumn: semantic_model_findings.finding_id"
    )
    return ($lines -join "`n")
}

function New-GovernanceSemanticModelDefinition {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$LakehouseId
    )

    $tables = Get-GovernanceModelTables
    $pbism = @{
        version = "4.2"
        settings = @{
            qnaEnabled = $true
        }
    } | ConvertTo-Json -Depth 10
    $database = "database`n`tcompatibilityLevel: 1702`n`tcompatibilityMode: powerBI"
    $modelLines = New-Object System.Collections.Generic.List[string]
    $modelLines.Add("model Model")
    $modelLines.Add("`tculture: en-US")
    $modelLines.Add("`tdefaultPowerBIDataSourceVersion: powerBI_V3")
    $modelLines.Add("`tdiscourageImplicitMeasures")
    $modelLines.Add("`tsourceQueryCulture: en-US")
    $modelLines.Add("")
    $modelLines.Add("expression DL_Lakehouse =")
    $modelLines.Add("`tlet")
    $modelLines.Add("`t`tSource = AzureStorage.DataLake(`"https://onelake.dfs.fabric.microsoft.com/$WorkspaceId/$LakehouseId`", [HierarchicalNavigation=true])")
    $modelLines.Add("`tin")
    $modelLines.Add("`t`tSource")
    $modelLines.Add("")
    foreach ($table in $tables) {
        $modelLines.Add("ref table $($table.name)")
    }

    $parts = New-Object System.Collections.Generic.List[object]
    $parts.Add((New-TextDefinitionPart -Path "definition.pbism" -Content $pbism))
    $parts.Add((New-TextDefinitionPart -Path "definition/database.tmdl" -Content $database))
    $parts.Add((New-TextDefinitionPart -Path "definition/model.tmdl" -Content ($modelLines -join "`n")))
    $parts.Add((New-TextDefinitionPart -Path "definition/relationships.tmdl" -Content (New-GovernanceRelationshipsTmdl)))
    foreach ($table in $tables) {
        $parts.Add((New-TextDefinitionPart -Path "definition/tables/$($table.name).tmdl" -Content (New-GovernanceTableTmdl -Table $table)))
    }

    return @{
        format = "TMDL"
        parts = $parts.ToArray()
    }
}

function New-OrUpdateSemanticModel {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$LakehouseId
    )

    $definition = New-GovernanceSemanticModelDefinition -WorkspaceId $WorkspaceId -LakehouseId $LakehouseId
    $existing = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $SemanticModelName -Type "SemanticModel"

    if ($existing) {
        Write-Host "Updating semantic model '$SemanticModelName' ($($existing.id))."
        Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/semanticModels/$($existing.id)/updateDefinition" -Body @{ definition = $definition } | Out-Null
        return $existing
    }

    Write-Host "Creating semantic model '$SemanticModelName'."
    $created = Invoke-FabricApi -Method POST -Url "$FabricApiBase/workspaces/$WorkspaceId/semanticModels" -Body @{
        displayName = $SemanticModelName
        description = "Direct Lake semantic model for duplicate semantic model governance results."
        definition = $definition
    }
    if ($created -and $created.id) {
        return $created
    }

    $semanticModel = Get-FabricItemByName -WorkspaceId $WorkspaceId -Name $SemanticModelName -Type "SemanticModel"
    if (-not $semanticModel) {
        throw "Semantic model '$SemanticModelName' was created asynchronously but could not be found after polling."
    }
    return $semanticModel
}

function New-OrCloneReport {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$SemanticModelId
    )

    if ([string]::IsNullOrWhiteSpace($SemanticModelId)) {
        throw "Report creation requires a semantic model ID."
    }

    $reports = Invoke-PowerBiApi -Method GET -Url "$PowerBiApiBase/groups/$WorkspaceId/reports"
    $existing = $reports.value | Where-Object { $_.name -eq $ReportName } | Select-Object -First 1
    if ($existing) {
        Write-Host "Reusing Power BI report '$ReportName' ($($existing.id))."
        return $existing
    }

    if ([string]::IsNullOrWhiteSpace($TemplateReportId)) {
        Write-Host "No template report ID supplied. Skipping report creation. Create the report from the generated semantic model, or rerun with -TemplateReportId."
        return $null
    }

    $sourceWorkspaceId = $TemplateReportWorkspaceId
    if ([string]::IsNullOrWhiteSpace($sourceWorkspaceId)) {
        $sourceWorkspaceId = $WorkspaceId
    }

    Write-Host "Cloning report template $TemplateReportId to '$ReportName' and binding it to semantic model $SemanticModelId."
    $body = @{
        name = $ReportName
        targetModelId = $SemanticModelId
        targetWorkspaceId = $WorkspaceId
    }
    return Invoke-PowerBiApi -Method POST -Url "$PowerBiApiBase/groups/$sourceWorkspaceId/reports/$TemplateReportId/Clone" -Body $body
}

Assert-CommandAvailable -Name "az"
Invoke-AzLogin

$workspace = New-OrGetWorkspace
$lakehouse = New-OrGetLakehouse -WorkspaceId $workspace.id

$initializeNotebookPath = Join-Path $RepoRoot "fabric\notebooks\initialize_governance_tables.py"
$sampleNotebookPath = Join-Path $RepoRoot "fabric\notebooks\load_sample_governance_data.py"
$scanNotebookPath = Join-Path $RepoRoot "fabric\notebooks\semantic_model_governance_scan.py"

$initializeNotebook = New-OrUpdateNotebook -WorkspaceId $workspace.id -LakehouseId $lakehouse.id -NotebookName $InitializeNotebookName -SourcePath $initializeNotebookPath
$sampleNotebook = New-OrUpdateNotebook -WorkspaceId $workspace.id -LakehouseId $lakehouse.id -NotebookName $SampleNotebookName -SourcePath $sampleNotebookPath
$scanNotebook = New-OrUpdateNotebook -WorkspaceId $workspace.id -LakehouseId $lakehouse.id -NotebookName $ScanNotebookName -SourcePath $scanNotebookPath -ApplyScanConfiguration

$initializePipeline = $null
$samplePipeline = $null
$scanPipeline = $null
if (-not $SkipPipelines) {
    $initializePipeline = New-OrUpdatePipeline `
        -WorkspaceId $workspace.id `
        -PipelineName $InitializePipelineName `
        -NotebookId $initializeNotebook.id `
        -ActivityName "Initialize governance tables" `
        -Description "Creates empty standardized governance Delta tables in the solution Lakehouse."

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

$initializationRun = $null
if (-not $SkipInitializationRun) {
    $initializationRun = Start-FabricNotebookRun -WorkspaceId $workspace.id -NotebookId $initializeNotebook.id -LakehouseId $lakehouse.id -LakehouseNameForRun $LakehouseName
}

$semanticModel = $null
if (-not $SkipSemanticModel) {
    $semanticModel = New-OrUpdateSemanticModel -WorkspaceId $workspace.id -LakehouseId $lakehouse.id
}

$reportShell = $null
if (-not $SkipReport -and $semanticModel) {
    $reportShell = New-OrCloneReport -WorkspaceId $workspace.id -SemanticModelId $semanticModel.id
}
elseif (-not $SkipReport) {
    Write-Host "Skipping report creation because semantic model creation was skipped."
}

$summary = [ordered]@{
    workspaceName = $WorkspaceName
    workspaceId = $workspace.id
    lakehouseName = $LakehouseName
    lakehouseId = $lakehouse.id
    initializeNotebookName = $InitializeNotebookName
    initializeNotebookId = $initializeNotebook.id
    sampleNotebookName = $SampleNotebookName
    sampleNotebookId = $sampleNotebook.id
    scanNotebookName = $ScanNotebookName
    scanNotebookId = $scanNotebook.id
    initializePipelineName = if ($initializePipeline) { $InitializePipelineName } else { $null }
    initializePipelineId = if ($initializePipeline) { $initializePipeline.id } else { $null }
    samplePipelineName = if ($samplePipeline) { $SamplePipelineName } else { $null }
    samplePipelineId = if ($samplePipeline) { $samplePipeline.id } else { $null }
    scanPipelineName = if ($scanPipeline) { $ScanPipelineName } else { $null }
    scanPipelineId = if ($scanPipeline) { $scanPipeline.id } else { $null }
    initializationRunAttempted = -not $SkipInitializationRun
    semanticModelName = if ($semanticModel) { $SemanticModelName } else { $null }
    semanticModelId = if ($semanticModel) { $semanticModel.id } else { $null }
    reportTemplateId = if ($TemplateReportId) { $TemplateReportId } else { $null }
    reportName = if ($reportShell) { $ReportName } else { $null }
    reportId = if ($reportShell) { $reportShell.id } else { $null }
    nextSteps = @(
        "Open the Fabric workspace and confirm the Lakehouse, notebooks, Data Pipelines, and semantic model are present.",
        "Attach or create a Fabric Environment that installs this package if your workspace does not support inline package install.",
        "Trigger the sample-load pipeline to validate sample data, then refresh the semantic model/report.",
        "If no template report was supplied, create the report from the generated semantic model using the report build guide.",
        "Configure scan scope, trigger the scan pipeline, refresh the semantic model/report, then schedule the pipeline."
    )
}

Write-Host ""
Write-Host "Provisioning complete."
$summary | ConvertTo-Json -Depth 10
