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
    $fontLicenseSource = Join-Path $projectRoot 'assets/fonts/licenses/fusion-pixel'
    $fontNotices = @(
        'OFL.txt',
        'LICENSES/ark-pixel/OFL.txt',
        'LICENSES/cubic-11/OFL.txt',
        'LICENSES/galmuri/LICENSE.txt'
    )
    foreach ($notice in $fontNotices) {
        if (-not (Test-Path -LiteralPath (Join-Path $fontLicenseSource $notice) -PathType Leaf)) {
            throw "Missing distribution notice: assets/fonts/licenses/fusion-pixel/$notice"
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
    $fontLicenseDirectory = Join-Path $licenseDirectory 'fonts/fusion-pixel'
    foreach ($notice in $fontNotices) {
        $destination = Join-Path $fontLicenseDirectory $notice
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $fontLicenseSource $notice) -Destination $destination -Force
    }
    Compress-Archive -LiteralPath @($executable, $package, $licenseDirectory) -DestinationPath $archive -Force
    Write-Output "Built: $outputDirectory"
    Write-Output "Archive: $archive"
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
