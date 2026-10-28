$ErrorActionPreference = 'Stop'

try {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $runner = Join-Path $PSScriptRoot 'run.ps1'
    $suites = @(
        'rules', 'purchase_query', 'combat', 'homing', 'ui', 'notifications',
        'modal', 'choice_actions', 'upgrade_previews', 'profile_modes', 'flow',
        'feedback', 'impact_feedback', 'projectile_painter', 'enemy_telegraphs',
        'content_expansion', 'content_presentation', 'relic_preview', 'relic_comparison',
        'trail_readability', 'rune_equip_preview', 'rune_equip_comparison', 'enemy_hit_style',
        'shop_locks', 'shop_lock_ui', 'shop_lock_flow', 'return_ring', 'return_ring_ui', 'return_ring_presentation',
        'projectile_capacity', 'benchmark_seed', 'player_foreground',
        'combat_upgrades', 'combat_upgrade_ui', 'upgrade_timing',
        'backpack_inventory', 'backpack_combat', 'backpack_queries',
        'backpack_flow', 'backpack_ui', 'backpack_targets', 'backpack_shop',
        'rogue_state', 'rogue_combat', 'rogue_ui', 'rogue_progress',
        'resonance_rules', 'resonance_combat', 'resonance_grid', 'resonance_ui',
        'rogue_resonance_state', 'rogue_resonance_combat', 'rogue_resonance_ui',
        'arena_rules', 'arena_flow', 'concise_ui',
        'dash_rules', 'dash_world', 'dash_flow', 'dash_ui',
        'dash_evasion', 'dash_evasion_world', 'dash_evasion_audio',
        'pulse_rules', 'pulse_world', 'pulse_flow', 'pulse_ui',
        'skill_relics', 'skill_relic_combat', 'skill_relic_ui',
        'control_bindings', 'controls_flow', 'controls_ui', 'gamepad_backpack'
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
