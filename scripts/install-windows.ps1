$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Target = Join-Path $env:LOCALAPPDATA 'ShiftDrop'
New-Item -ItemType Directory -Force $Target | Out-Null
$Bundle = Join-Path $RepoRoot 'ShiftDrop'
if (Test-Path (Join-Path $Bundle 'ShiftDrop.exe')) {
    $App = Join-Path $Target 'app'
    New-Item -ItemType Directory -Force $App | Out-Null
    Copy-Item (Join-Path $Bundle '*') $App -Recurse -Force
    $Executable = Join-Path $App 'ShiftDrop.exe'
    $Arguments = ''
} else {
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
