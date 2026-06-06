param(
    [Parameter(Position=0)]
    [string]$Command = "",
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs = @()
)

function Show-Usage {
    Write-Host @"
helm-envoy — environment-aware Helm value file manager

Usage:
  helm envoy install <release> <chart> --environment <env> [-- <helm flags>]
  helm envoy upgrade <release> <chart> --environment <env> [-- <helm flags>]
  helm envoy list-environments <chart-path>

Flags:
  --environment <env>   Environment name to resolve value files for

Value file resolution order (all that exist are applied, low to high priority):
  values.yaml
  values-<env>.yaml
  values-<env>.local.yaml  (local overrides, if present)

Examples:
  helm envoy install my-app ./chart --environment production
  helm envoy upgrade my-app ./chart --environment staging -- --atomic --timeout 5m
  helm envoy list-environments ./chart
"@
}

function Find-EnvValueFiles {
    param([string]$ChartPath)
    Get-ChildItem -Path $ChartPath -Filter "values-*.yaml" -File |
        ForEach-Object { $_.Name -replace '^values-', '' -replace '\.yaml$', '' } |
        Sort-Object -Unique
}

function Invoke-ListEnvironments {
    param([string]$ChartPath = ".")

    if (-not (Test-Path $ChartPath -PathType Container)) {
        Write-Error "chart path '$ChartPath' is not a directory."
        exit 1
    }

    $envs = Find-EnvValueFiles -ChartPath $ChartPath

    if ($envs.Count -eq 0) {
        Write-Host "No environment value files found in '$ChartPath'."
        Write-Host "Expected files named: values-<environment>.yaml"
    } else {
        Write-Host "Environments found in '$ChartPath':"
        foreach ($env in $envs) {
            $file = Join-Path $ChartPath "values-$env.yaml"
            Write-Host "  - $env  ($file)"
        }
    }
}

function Build-ValueFileArgs {
    param([string]$ChartPath, [string]$Environment)
    $args = @()

    $baseValues = Join-Path $ChartPath "values.yaml"
    if (Test-Path $baseValues) {
        $args += "-f", $baseValues
    }

    $envValues = Join-Path $ChartPath "values-$Environment.yaml"
    if (-not (Test-Path $envValues)) {
        Write-Error "no value file found for environment '$Environment'."
        Write-Error "Expected: $envValues"
        Write-Host ""
        Write-Host "Available environments:" -ForegroundColor Yellow
        Find-EnvValueFiles -ChartPath $ChartPath | ForEach-Object { Write-Host "  - $_" }
        exit 1
    }
    $args += "-f", $envValues

    $localValues = Join-Path $ChartPath "values-$Environment.local.yaml"
    if (Test-Path $localValues) {
        $args += "-f", $localValues
    }

    return $args
}

function Invoke-HelmCommand {
    param([string]$HelmCmd, [string[]]$Args)

    if ($Args.Count -lt 2) {
        Write-Error "Usage: helm envoy $HelmCmd <release> <chart> --environment <env>"
        exit 1
    }

    $release = $Args[0]
    $chart   = $Args[1]
    $remaining = $Args[2..($Args.Count - 1)]

    $environment = ""
    $extraArgs   = @()
    $i = 0
    while ($i -lt $remaining.Count) {
        if ($remaining[$i] -eq "--environment" -and ($i + 1) -lt $remaining.Count) {
            $environment = $remaining[$i + 1]
            $i += 2
        } elseif ($remaining[$i] -eq "--") {
            $extraArgs += $remaining[($i+1)..($remaining.Count - 1)]
            break
        } else {
            $extraArgs += $remaining[$i]
            $i++
        }
    }

    if ([string]::IsNullOrEmpty($environment)) {
        Write-Error "--environment <name> is required."
        Write-Host "Use 'helm envoy list-environments <chart>' to see available environments." -ForegroundColor Yellow
        exit 1
    }

    # Resolve chart path for local charts
    if ($chart -match '^[./\\]') {
        $chartPath = $chart
    } else {
        $chartPath = "."
    }

    $valueArgs = Build-ValueFileArgs -ChartPath $chartPath -Environment $environment

    Write-Host "helm-envoy: running helm $HelmCmd for environment '$environment'"
    Write-Host "  release : $release"
    Write-Host "  chart   : $chart"
    Write-Host "  values  : $($valueArgs -join ' ')"
    if ($extraArgs.Count -gt 0) { Write-Host "  flags   : $($extraArgs -join ' ')" }
    Write-Host ""

    & helm $HelmCmd $release $chart @valueArgs @extraArgs
}

switch ($Command.ToLower()) {
    "install"              { Invoke-HelmCommand -HelmCmd "install" -Args $RemainingArgs }
    "upgrade"              { Invoke-HelmCommand -HelmCmd "upgrade" -Args $RemainingArgs }
    "list-environments"    { Invoke-ListEnvironments -ChartPath ($RemainingArgs[0] ?? ".") }
    "--list-environments"  { Invoke-ListEnvironments -ChartPath ($RemainingArgs[0] ?? ".") }
    { $_ -in "help", "--help", "-h", "" } { Show-Usage }
    default {
        Write-Error "unknown command '$Command'."
        Write-Host ""
        Show-Usage
        exit 1
    }
}
