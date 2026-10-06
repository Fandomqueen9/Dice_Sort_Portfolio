param(
    [string]$ServerUrl = "http://REPLACE-WITH-SERVER-IP:8000"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$serverDir = Join-Path $dist "dicegame-server"
$clientDir = Join-Path $dist "dicegame-client"

function Copy-Lf($source, $destination) {
    $text = [System.IO.File]::ReadAllText($source) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($destination, $text, (New-Object System.Text.UTF8Encoding($false)))
}

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $serverDir, $clientDir | Out-Null

# Server bundle
$backendDest = Join-Path $serverDir "backend"
New-Item -ItemType Directory -Path $backendDest | Out-Null
Get-ChildItem (Join-Path $root "backend") -File |
    Where-Object { $_.Extension -in ".py", ".txt" } |
    Copy-Item -Destination $backendDest
Copy-Lf (Join-Path $PSScriptRoot "server\install.sh") (Join-Path $serverDir "install.sh")
Copy-Lf (Join-Path $PSScriptRoot "server\README.txt") (Join-Path $serverDir "README.txt")
Copy-Lf (Join-Path $PSScriptRoot "dicegame-backend.service") (Join-Path $serverDir "dicegame-backend.service")

# Client bundle
Copy-Lf (Join-Path $PSScriptRoot "client\run.sh") (Join-Path $clientDir "run.sh")
Copy-Lf (Join-Path $PSScriptRoot "client\README.txt") (Join-Path $clientDir "README.txt")
[System.IO.File]::WriteAllText((Join-Path $clientDir "server_url.txt"), "$ServerUrl`n")

$binary = Join-Path $root "client\Dice Sorting Game.x86_64"
if (Test-Path $binary) {
    Copy-Item $binary $clientDir
    $newestSource = Get-ChildItem (Join-Path $root "client") -Recurse -File -Include *.gd, *.tscn, *.gdshader, project.godot |
        Where-Object { $_.FullName -notmatch '\\\.godot\\' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ((Get-Item $binary).LastWriteTime -lt $newestSource.LastWriteTime) {
        Write-Warning "The exported binary is older than $($newestSource.Name). Re-export from Godot (Project > Export > Linux/X11) and run this script again."
    }
} else {
    Write-Warning "No exported binary at client\Dice Sorting Game.x86_64. Export from Godot (Project > Export > Linux/X11) and run this script again."
}

Push-Location $dist
tar -czf dicegame-server.tar.gz dicegame-server
tar -czf dicegame-client.tar.gz dicegame-client
Pop-Location

Write-Host ""
Write-Host "Bundles written to $dist"
Write-Host "  dicegame-server.tar.gz  -> the server VM"
Write-Host "  dicegame-client.tar.gz  -> the Kali VM and the admin VM"
