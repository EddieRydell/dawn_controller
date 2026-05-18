param(
    [Parameter(Mandatory = $true)]
    [string]$Top,

    [Parameter(Mandatory = $true)]
    [string]$Sources,

    [switch]$Dump
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$simRoot = Join-Path $repoRoot "build\sim\$Top"
New-Item -ItemType Directory -Force -Path $simRoot | Out-Null

$sourceList = $Sources.Split(",") | ForEach-Object {
    Join-Path $repoRoot $_.Trim()
}

Push-Location $simRoot
try {
    & xvlog --nolog -sv @sourceList
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & xelab --nolog $Top -s "${Top}_sim"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $xsimArgs = @("--nolog", "${Top}_sim", "--runall")
    if ($Dump) {
        $xsimArgs += "--testplusarg"
        $xsimArgs += "DUMP"
        $xsimArgs += "--wdb"
        $xsimArgs += "$Top.wdb"
    }

    & xsim @xsimArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        $patterns = @(
            "*.pb",
            "*.jou",
            "*.log",
            "dfx_runtime.txt",
            "xsim_*.backup.log",
            "xsim_*.backup.jou"
        )
        if (-not $Dump) {
            $patterns += "*.wdb"
            $patterns += "*.vcd"
        }

        Get-ChildItem -Force -File | Where-Object {
            $name = $_.Name
            $patterns | Where-Object { $name -like $_ }
        } | Remove-Item -Force

        Get-ChildItem -Force -Recurse -File -Path "xsim.dir" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*.log" } |
            Remove-Item -Force
    }

    exit $exitCode
} finally {
    Pop-Location
}
