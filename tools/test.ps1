$ErrorActionPreference = 'Stop'

try {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $runner = Join-Path $PSScriptRoot 'run.ps1'
    $suites = @(
        'rules', 'purchase_query', 'combat', 'homing', 'ui', 'notifications',
        'modal', 'choice_actions', 'upgrade_previews', 'shop_actions',
        'shop_details', 'shop_availability', 'profile_modes', 'flow',
        'feedback', 'impact_feedback', 'projectile_painter', 'enemy_telegraphs',
        'simulation_shop', 'content_expansion', 'content_presentation'
    )
    foreach ($suite in $suites) {
        & $runner --headless --script "res://tests/test_$suite.gd"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    foreach ($diagnostic in @('--smoke', '--autoplay', '--shop-preview', '--benchmark', '--capture-only')) {
        & $runner --headless --script res://tests/test_profile_modes.gd '--' $diagnostic
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    $pythonCandidates = if ($env:BROXY_PYTHON) { @($env:BROXY_PYTHON) } else { @('python3', 'python', 'py') }
    $pythonCommand = $null
    foreach ($candidate in $pythonCandidates) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue
        if ($command -and $command.Source -notmatch '[\\/]Microsoft[\\/]WindowsApps[\\/]') {
            $pythonCommand = $command.Source
            break
        }
    }
    if (-not $pythonCommand) { throw 'Python 3 not found. Install Python 3 or set BROXY_PYTHON to its executable.' }

    $previousCachePrefix = $env:PYTHONPYCACHEPREFIX
    try {
        $env:PYTHONPYCACHEPREFIX = Join-Path ([IO.Path]::GetTempPath()) 'broxy-pycache'
        # Windows PowerShell exposes native stderr as errors during redirection;
        # unittest normally prints its successful progress to that stream.
        $ErrorActionPreference = 'Continue'
        & $pythonCommand -m unittest discover -s (Join-Path $projectRoot 'tests') -p 'test_*.py' 2>&1 |
            ForEach-Object {
                if ($_ -is [Management.Automation.ErrorRecord]) {
                    Write-Output $_.Exception.Message
                } else {
                    Write-Output ([string] $_)
                }
            }
        $pythonExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
        $env:PYTHONPYCACHEPREFIX = $previousCachePrefix
    }
    exit $pythonExitCode
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
