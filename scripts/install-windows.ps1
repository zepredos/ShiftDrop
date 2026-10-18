$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Target = Join-Path $env:LOCALAPPDATA 'ShiftDrop'
$Bundle = Join-Path $RepoRoot 'ShiftDrop'
if (Test-Path (Join-Path $Bundle 'ShiftDrop.exe')) {
    $App = Join-Path $Target 'app'
    New-Item -ItemType Directory -Force $App | Out-Null
    Copy-Item (Join-Path $Bundle '*') $App -Recurse -Force
    $Executable = Join-Path $App 'ShiftDrop.exe'
    $Arguments = ''
} else {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw 'Source installation requires Python 3.11 or newer and the Python launcher. Use the compiled ShiftDrop-Windows binary ZIP to run without Python, or install Python 3.12 and try again.'
    }
    $DetectedVersion = & py -3 -c 'import sys; print(sys.version.split()[0])'
    if ($LASTEXITCODE -ne 0) { throw 'Could not start Python. Use the compiled ShiftDrop-Windows binary ZIP, or install Python 3.12 and try again.' }
    if ([version]$DetectedVersion -lt [version]'3.11') {
        throw "Source installation requires Python 3.11 or newer; the launcher selected $DetectedVersion. Use the compiled ShiftDrop-Windows binary ZIP to run without Python, or install Python 3.12 and try again."
    }
    $Venv = Join-Path $Target 'venv'
    py -3 -m venv $Venv
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.11 or later is required.' }
    $Python = Join-Path $Venv 'Scripts\python.exe'
    & $Python -m pip install $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not install ShiftDrop dependencies.' }
    $Executable = Join-Path $Venv 'Scripts\pythonw.exe'
    $Arguments = '-m shiftdrop'
}
$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'ShiftDrop.lnk'))
$Shortcut.TargetPath = $Executable
$Shortcut.Arguments = $Arguments
$Shortcut.WorkingDirectory = $Target
$Shortcut.Save()
Write-Output 'ShiftDrop installed. Open it from the Start menu.'
Write-Output 'For local image-to-text recognition, install Tesseract and add it to PATH.'
