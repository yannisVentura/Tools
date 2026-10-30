#Requires -Version 5.1
<#
.SYNOPSIS
    Maintenance silencieuse du poste : vérification des fichiers système (SFC) puis mise à jour des applications (winget).

.DESCRIPTION
    Conçu pour être exécuté par une tâche planifiée sous le compte SYSTEM :
    aucune fenêtre, aucune pop-up, aucune validation demandée à l'utilisateur.

    Journal volontairement minimal : une ligne par commande, OK ou ERREUR avec le code retour.
    Un seul fichier, plafonné à MaxLogLines lignes (les plus anciennes sont supprimées).

    Exemple de journal :
        2026-11-04 12:00:02 | sfc /scannow         | OK
        2026-11-04 12:38:47 | winget upgrade --all | ERREUR code -1978335226 (0x8A150006)

.PARAMETER WithDism
    Exécute DISM /Online /Cleanup-Image /RestoreHealth avant SFC (recommandation Microsoft).

.PARAMETER LogPath
    Fichier journal. Par défaut : %ProgramData%\SystemMaintenance\Maintenance.log

.PARAMETER MaxLogLines
    Nombre maximal de lignes conservées dans le journal. Par défaut : 500 (plusieurs années d'historique).

.EXAMPLE
    .\Invoke-SystemMaintenance.ps1 -Verbose
    Test manuel depuis une console PowerShell lancée en administrateur.

.NOTES
    Codes de sortie du script : 0 = toutes les commandes OK, 1 = au moins une erreur.
    Détails en cas d'erreur : SFC -> %WINDIR%\Logs\CBS\CBS.log, DISM -> %WINDIR%\Logs\DISM\dism.log,
    winget -> code à rechercher sur https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
#>
[CmdletBinding()]
param(
    [switch]$WithDism,

    [ValidateNotNullOrEmpty()]
    [string]$LogPath = (Join-Path -Path $env:ProgramData -ChildPath 'SystemMaintenance\Maintenance.log'),

    [ValidateRange(10, 100000)]
    [int]$MaxLogLines = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 0x8A15002B (APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE) : aucune mise à jour disponible, ce n'est pas une erreur.
$WingetSuccessCodes = @(0, -1978335189)

#region Fonctions

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Result
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} | {1,-20} | {2}' -f (Get-Date), $Command, $Result
    Write-Verbose -Message $line

    try {
        $directory = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch {
        Write-Warning -Message "Écriture du journal impossible : $($_.Exception.Message)"
    }
}

function Limit-LogSize {
    try {
        if (Test-Path -LiteralPath $LogPath) {
            $lines = @(Get-Content -LiteralPath $LogPath -Encoding UTF8)
            if ($lines.Count -gt $MaxLogLines) {
                $lines | Select-Object -Last $MaxLogLines | Set-Content -LiteralPath $LogPath -Encoding UTF8
            }
        }
    }
    catch { }
}

function Format-Error {
    param([int]$Code)
    return 'ERREUR code {0} (0x{1:X8})' -f $Code, $Code
}

function Get-NativeSystemDirectory {
    # Un processus 32 bits sur un OS 64 bits est redirigé vers SysWOW64 : sfc.exe y échoue. Sysnative contourne la redirection.
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        return Join-Path -Path $env:SystemRoot -ChildPath 'Sysnative'
    }
    return Join-Path -Path $env:SystemRoot -ChildPath 'System32'
}

function Get-WingetPath {
    # Contexte utilisateur : l'alias d'exécution winget.exe est dans le PATH.
    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    # Contexte SYSTEM : pas d'alias, on cible directement le paquet App Installer le plus récent.
    $appsRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps'
    Get-ChildItem -LiteralPath $appsRoot -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
        Sort-Object -Property { [version](($_.Name -split '_')[1]) } -Descending |
        ForEach-Object { Join-Path -Path $_.FullName -ChildPath 'winget.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
}

function Invoke-Step {
    <#
        Exécute une commande sans fenêtre, en ignorant sa sortie, et écrit une seule ligne de journal.
        Retourne $true si le code retour fait partie des codes de succès.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [int[]]$SuccessCodes = @(0),

        [string]$WorkingDirectory = $env:SystemRoot
    )

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory `
            -WindowStyle Hidden -Wait -PassThru
        $code = $process.ExitCode

        if ($SuccessCodes -contains $code) {
            Write-Log -Command $Label -Result 'OK'
            return $true
        }

        Write-Log -Command $Label -Result (Format-Error $code)
        return $false
    }
    catch {
        Write-Log -Command $Label -Result ('ERREUR lancement impossible : {0}' -f $_.Exception.Message)
        return $false
    }
}

#endregion

#region Exécution

$allOk = $true
$systemDirectory = Get-NativeSystemDirectory

if ($WithDism) {
    $allOk = (Invoke-Step -Label 'DISM /RestoreHealth' -FilePath (Join-Path $systemDirectory 'Dism.exe') `
        -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth', '/NoRestart', '/Quiet') -and $allOk
}

$allOk = (Invoke-Step -Label 'sfc /scannow' -FilePath (Join-Path $systemDirectory 'sfc.exe') -ArgumentList '/scannow') -and $allOk

$wingetPath = Get-WingetPath
if ($wingetPath) {
    $allOk = (Invoke-Step -Label 'winget upgrade --all' -FilePath $wingetPath -WorkingDirectory (Split-Path -Path $wingetPath -Parent) `
        -ArgumentList 'upgrade', '--all', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity' `
        -SuccessCodes $WingetSuccessCodes) -and $allOk
}
else {
    Write-Log -Command 'winget upgrade --all' -Result 'ERREUR winget introuvable (installer / mettre à jour App Installer)'
    $allOk = $false
}

Limit-LogSize

exit [int](-not $allOk)

#endregion
