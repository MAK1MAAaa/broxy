$ErrorActionPreference = 'Stop'

try {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $runner = Join-Path $PSScriptRoot 'run.ps1'
    $template = Join-Path $projectRoot '.tools/windows_release_x86_64.exe'
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        throw 'Windows export template not found. Run: python tools/fetch_windows_template.py'
    }
    $notices = @('Godot-LICENSE.txt', 'Godot-COPYRIGHT.txt', 'README.md')
    foreach ($notice in $notices) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "assets/licenses/$notice") -PathType Leaf)) {
            throw "Missing distribution notice: assets/licenses/$notice"
        }
    }

    $outputDirectory = Join-Path $projectRoot 'build/Embers-windows-x86_64'
    $executable = Join-Path $outputDirectory 'Embers.exe'
    $package = Join-Path $outputDirectory 'Embers.pck'
    $licenseDirectory = Join-Path $outputDirectory 'licenses'
    $archive = Join-Path $projectRoot 'build/Embers-windows-x86_64.zip'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    & $runner --headless --editor --import --quit
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $runner --headless --export-release 'Windows Desktop' $executable
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    foreach ($artifact in @($executable, $package)) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "Export did not produce the required file: $artifact"
        }
    }

    New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
    foreach ($notice in $notices) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "assets/licenses/$notice") -Destination $licenseDirectory -Force
    }
    Compress-Archive -LiteralPath @($executable, $package, $licenseDirectory) -DestinationPath $archive -Force
    Write-Output "Built: $outputDirectory"
    Write-Output "Archive: $archive"
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
