$ErrorActionPreference = 'Stop'

function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string] $Value)

    # ProcessStartInfo.Arguments follows the Windows C runtime quoting rules.
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

try {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else {
        Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
    }
    $godotCommand = Get-Command -Name $godot -CommandType Application -ErrorAction SilentlyContinue
    if (-not $godotCommand) {
        throw 'Godot not found. Run: python tools/fetch_godot.py --platform windows, or set GODOT_BIN.'
    }

    $nativeArguments = @('--path', $projectRoot) + $args
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $godotCommand.Source
    $startInfo.Arguments = ($nativeArguments | ForEach-Object { ConvertTo-WindowsArgument ([string] $_) }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        # Drain both pipes concurrently so large native output cannot deadlock.
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $standardOutput = $outputTask.GetAwaiter().GetResult()
        $standardError = $errorTask.GetAwaiter().GetResult()
    } finally {
        $process.Dispose()
    }
    if ($standardOutput.Length -gt 0) {
        $standardOutput.TrimEnd([char[]] "`r`n") -split '\r?\n' | Write-Output
    }
    if ($standardError.Length -gt 0) {
        Write-Error -Message $standardError.TrimEnd([char[]] "`r`n") -ErrorAction Continue
    }
    exit $exitCode
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
