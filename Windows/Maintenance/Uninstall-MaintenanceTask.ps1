#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Supprime la tâche planifiée de maintenance et, en option, le dossier d'installation (script + journaux).

.DESCRIPTION
    winget et le module PowerShell Microsoft.WinGet.Client installés par Install-MaintenanceTask.ps1 sont conservés :
    ce sont des composants Windows utiles en dehors de cet outil.

.PARAMETER TaskName
    Nom de la tâche planifiée à supprimer.

.PARAMETER InstallPath
    Dossier d'installation. Par défaut : %ProgramData%\SystemMaintenance

.PARAMETER RemoveFiles
    Supprime aussi le dossier d'installation et les journaux.

.EXAMPLE
    .\Uninstall-MaintenanceTask.ps1 -RemoveFiles
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'Maintenance hebdomadaire (SFC + winget)',

    [ValidateNotNullOrEmpty()]
    [string]$InstallPath = (Join-Path -Path $env:ProgramData -ChildPath 'SystemMaintenance'),

    [switch]$RemoveFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$task = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
if ($task) {
    if ($PSCmdlet.ShouldProcess($TaskName, 'Supprimer la tâche planifiée')) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false
        Write-Output "Tâche '$TaskName' supprimée."

        # Trace dans le journal, sauf si celui-ci va être supprimé avec le dossier.
        $logPath = Join-Path -Path $InstallPath -ChildPath 'Maintenance.log'
        if (-not $RemoveFiles -and (Test-Path -LiteralPath $InstallPath)) {
            Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('{0:dd\/MM\/yyyy HH\:mm\:ss} | {1,-20} | {2}' -f (Get-Date), 'Suppression tâche', 'OK')
        }
    }
}
else {
    Write-Output "Tâche '$TaskName' introuvable, rien à supprimer."
}

if ($RemoveFiles -and (Test-Path -LiteralPath $InstallPath)) {
    if ($PSCmdlet.ShouldProcess($InstallPath, 'Supprimer le dossier et son contenu')) {
        Remove-Item -LiteralPath $InstallPath -Recurse -Force
        Write-Output "Dossier '$InstallPath' supprimé."
    }
}
