#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe le script de maintenance et crée la tâche planifiée qui l'exécute en silence sous le compte SYSTEM.

.DESCRIPTION
    - Copie Invoke-SystemMaintenance.ps1 dans un dossier protégé (écriture réservée à SYSTEM et aux administrateurs,
      afin qu'un utilisateur standard ne puisse pas modifier un script exécuté avec les privilèges SYSTEM).
    - Crée (ou remplace) une tâche planifiée hebdomadaire :
        * compte SYSTEM, privilèges les plus élevés : aucune fenêtre ni invite UAC, que l'utilisateur soit connecté ou non ;
        * rattrapage si le poste était éteint à l'heure prévue ;
        * uniquement si le réseau est disponible ;
        * une seule instance à la fois, durée maximale 4 heures.

.PARAMETER InstallPath
    Dossier d'installation. Par défaut : %ProgramData%\SystemMaintenance

.PARAMETER TaskName
    Nom de la tâche planifiée.

.PARAMETER DayOfWeek
    Jour d'exécution hebdomadaire. Par défaut : Wednesday (mercredi).

.PARAMETER At
    Heure d'exécution. Par défaut : 12:00 (le poste a plus de chances d'être allumé qu'en pleine nuit).

.PARAMETER WithDism
    Ajoute l'étape DISM /RestoreHealth avant SFC.

.PARAMETER RunNow
    Lance la tâche immédiatement après sa création (test).

.EXAMPLE
    .\Install-MaintenanceTask.ps1

.EXAMPLE
    .\Install-MaintenanceTask.ps1 -DayOfWeek Sunday -At '10:30' -WithDism -RunNow
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InstallPath = (Join-Path -Path $env:ProgramData -ChildPath 'SystemMaintenance'),

    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'Maintenance hebdomadaire (SFC + winget)',

    [DayOfWeek]$DayOfWeek = [DayOfWeek]::Wednesday,

    [datetime]$At = '12:00',

    [switch]$WithDism,

    [switch]$RunNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptName = 'Invoke-SystemMaintenance.ps1'
$sourceScript = Join-Path -Path $PSScriptRoot -ChildPath $scriptName
$targetScript = Join-Path -Path $InstallPath -ChildPath $scriptName

if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Script source introuvable : $sourceScript"
}

# --- Dossier protégé ----------------------------------------------------------------------------
# SID plutôt que noms de groupes : fonctionne quelle que soit la langue de Windows ("Administrateurs", "Utilisateurs"...).
$sidSystem         = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
$sidAdministrators = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
$sidUsers          = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-545'

if ($PSCmdlet.ShouldProcess($InstallPath, 'Créer le dossier et restreindre ses permissions')) {
    if (-not (Test-Path -LiteralPath $InstallPath)) {
        New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
    }

    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow       = [Security.AccessControl.AccessControlType]::Allow

    $acl = New-Object -TypeName Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # coupe l'héritage du parent
    $acl.SetOwner($sidAdministrators)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidSystem, 'FullControl', $inheritance, $propagation, $allow)))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidAdministrators, 'FullControl', $inheritance, $propagation, $allow)))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidUsers, 'ReadAndExecute', $inheritance, $propagation, $allow)))
    Set-Acl -LiteralPath $InstallPath -AclObject $acl
}

if ($PSCmdlet.ShouldProcess($targetScript, 'Copier le script de maintenance')) {
    Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
    Unblock-File -LiteralPath $targetScript   # retire la marque "téléchargé depuis Internet"
}

# --- Tâche planifiée ----------------------------------------------------------------------------
$powershellExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $targetScript
if ($WithDism) {
    $arguments += ' -WithDism'
}

$action    = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory $InstallPath
$trigger   = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $DayOfWeek -At $At
# Compte SYSTEM (S-1-5-18) : s'exécute dans la session 0, invisible pour l'utilisateur connecté.
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 30)

$logPath = Join-Path -Path $InstallPath -ChildPath 'Maintenance.log'

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "Exécute sfc /scannow puis winget upgrade --all en arrière-plan. Journal : $logPath"

if ($PSCmdlet.ShouldProcess($TaskName, 'Enregistrer la tâche planifiée')) {
    try {
        Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -InputObject $task -Force | Out-Null
        $result = 'OK'
    }
    catch {
        $result = 'ERREUR {0}' -f $_.Exception.Message
        throw
    }
    finally {
        # Même format que le script de maintenance : une ligne, OK ou ERREUR.
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('{0:yyyy-MM-dd HH:mm:ss} | {1,-20} | {2}' -f (Get-Date), 'Installation tâche', $result)
    }

    Write-Output ("Tâche '{0}' enregistrée : chaque {1} à {2:HH\:mm}, sous SYSTEM." -f $TaskName, $DayOfWeek, $At)
    Write-Output ("Journal : {0}" -f $logPath)

    if ($RunNow) {
        Start-ScheduledTask -TaskName $TaskName -TaskPath '\'
        Write-Output 'Tâche démarrée. Le résultat apparaîtra dans le journal à la fin de son exécution.'
    }
}
