#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Maintient un poste Windows 10 sur Windows 10 : bloque la proposition de mise à niveau vers Windows 11
    et l'évaluation de compatibilité qui la prépare.

.DESCRIPTION
    - Applique la stratégie Windows Update « Sélectionner la version cible de la mise à jour des fonctionnalités »
      (TargetReleaseVersion / ProductVersion / TargetReleaseVersionInfo) : méthode documentée par Microsoft pour
      rester sur Windows 10 22H2. Fonctionne aussi sur l'édition Famille, où la stratégie est écrite dans le Registre.
    - Désactive les tâches planifiées de l'évaluateur de compatibilité (Microsoft Compatibility Appraiser,
      processus CompatTelRunner.exe) et de l'Assistant Mise à jour, puis arrête CompatTelRunner.exe s'il tourne.
    - Avec -Revert, annule tout : supprime la stratégie et réactive les tâches.

    Chaque action produit une ligne « OK » / « IGNORÉ » / « ERREUR » ; un échec isolé n'arrête pas les autres actions.

.PARAMETER Revert
    Annule le blocage (retour au comportement par défaut de Windows Update).

.PARAMETER TargetReleaseVersionInfo
    Version de Windows 10 à conserver. Par défaut : 22H2 (dernière version de Windows 10).

.EXAMPLE
    .\Block-Windows11Upgrade.ps1

.EXAMPLE
    .\Block-Windows11Upgrade.ps1 -WhatIf

.EXAMPLE
    .\Block-Windows11Upgrade.ps1 -Revert
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Revert,

    [ValidatePattern('^\d{2}H\d$')]
    [string]$TargetReleaseVersionInfo = '22H2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

# Tâches qui évaluent la compatibilité Windows 11 ou relancent l'Assistant Mise à jour.
# Toutes n'existent pas sur chaque build : une tâche absente est simplement ignorée.
$tasks = @(
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser Exp' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
    @{ Path = '\Microsoft\Windows\UpdateOrchestrator\';     Name = 'UpdateAssistant' }
    @{ Path = '\Microsoft\Windows\UpdateOrchestrator\';     Name = 'UpdateAssistantCalendarRun' }
    @{ Path = '\Microsoft\Windows\UpdateOrchestrator\';     Name = 'UpdateAssistantWakeupRun' }
)

$script:errors = 0

function Write-Result {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet('OK', 'IGNORÉ', 'ERREUR')][string]$Status,
        [string]$Detail
    )
    $color = @{ 'OK' = 'Green'; 'IGNORÉ' = 'DarkGray'; 'ERREUR' = 'Red' }[$Status]
    if ($Status -eq 'ERREUR') { $script:errors++ }
    Write-Host ('{0,-45} {1,-7} {2}' -f $Step, $Status, $Detail) -ForegroundColor $color
}

# --- Garde-fou : Windows 10 uniquement ----------------------------------------------------------
$os = Get-CimInstance -ClassName Win32_OperatingSystem
if ([int]$os.BuildNumber -ge 22000) {
    throw "Ce poste est déjà sous Windows 11 ($($os.Caption), build $($os.BuildNumber)) : rien à bloquer."
}
Write-Host "$($os.Caption) (build $($os.BuildNumber))"

# --- Stratégie Windows Update -------------------------------------------------------------------
if ($Revert) {
    foreach ($name in 'TargetReleaseVersion', 'ProductVersion', 'TargetReleaseVersionInfo') {
        try {
            if ($null -eq (Get-ItemProperty -LiteralPath $policyKey -Name $name -ErrorAction SilentlyContinue)) {
                Write-Result -Step "Stratégie $name" -Status 'IGNORÉ' -Detail 'absente'
            }
            elseif ($PSCmdlet.ShouldProcess("$policyKey\$name", 'Supprimer la valeur')) {
                Remove-ItemProperty -LiteralPath $policyKey -Name $name
                Write-Result -Step "Stratégie $name" -Status 'OK' -Detail 'supprimée'
            }
        }
        catch { Write-Result -Step "Stratégie $name" -Status 'ERREUR' -Detail $_.Exception.Message }
    }
}
else {
    $values = [ordered]@{
        TargetReleaseVersion     = @{ Type = 'DWord';  Value = 1 }
        ProductVersion           = @{ Type = 'String'; Value = 'Windows 10' }
        TargetReleaseVersionInfo = @{ Type = 'String'; Value = $TargetReleaseVersionInfo }
    }
    foreach ($name in $values.Keys) {
        try {
            if ($PSCmdlet.ShouldProcess("$policyKey\$name", "Définir à '$($values[$name].Value)'")) {
                if (-not (Test-Path -LiteralPath $policyKey)) {
                    New-Item -Path $policyKey -Force | Out-Null
                }
                New-ItemProperty -LiteralPath $policyKey -Name $name -PropertyType $values[$name].Type `
                    -Value $values[$name].Value -Force | Out-Null
                Write-Result -Step "Stratégie $name" -Status 'OK' -Detail "= $($values[$name].Value)"
            }
        }
        catch { Write-Result -Step "Stratégie $name" -Status 'ERREUR' -Detail $_.Exception.Message }
    }
}

# --- Tâches planifiées --------------------------------------------------------------------------
foreach ($task in $tasks) {
    $step = "Tâche $($task.Name)"
    try {
        $scheduled = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue
        if (-not $scheduled) {
            Write-Result -Step $step -Status 'IGNORÉ' -Detail 'absente sur ce poste'
            continue
        }
        $wantedState = if ($Revert) { 'Ready' } else { 'Disabled' }
        if (($scheduled.State -eq 'Disabled') -eq (-not $Revert)) {
            Write-Result -Step $step -Status 'IGNORÉ' -Detail "déjà $($scheduled.State)"
            continue
        }
        if ($PSCmdlet.ShouldProcess("$($task.Path)$($task.Name)", $(if ($Revert) { 'Activer' } else { 'Désactiver' }))) {
            if ($Revert) {
                Enable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name | Out-Null
            }
            else {
                Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name | Out-Null
            }
            Write-Result -Step $step -Status 'OK' -Detail $wantedState
        }
    }
    catch {
        # Certaines tâches de UpdateOrchestrator sont protégées et refusées même à un administrateur.
        Write-Result -Step $step -Status 'ERREUR' -Detail $_.Exception.Message
    }
}

# --- Processus en cours -------------------------------------------------------------------------
if (-not $Revert) {
    $running = Get-Process -Name 'CompatTelRunner' -ErrorAction SilentlyContinue
    if (-not $running) {
        Write-Result -Step 'Processus CompatTelRunner.exe' -Status 'IGNORÉ' -Detail 'non lancé'
    }
    elseif ($PSCmdlet.ShouldProcess('CompatTelRunner.exe', 'Arrêter')) {
        try {
            $running | Stop-Process -Force
            Write-Result -Step 'Processus CompatTelRunner.exe' -Status 'OK' -Detail 'arrêté'
        }
        catch { Write-Result -Step 'Processus CompatTelRunner.exe' -Status 'ERREUR' -Detail $_.Exception.Message }
    }
}

if ($script:errors -gt 0) {
    Write-Warning "$($script:errors) action(s) en erreur : voir les lignes ERREUR ci-dessus."
    exit 1
}
exit 0
