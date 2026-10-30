#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe le script de maintenance et crée la tâche planifiée qui l'exécute en silence sous le compte SYSTEM.

.DESCRIPTION
    - Copie Invoke-SystemMaintenance.ps1 dans un dossier protégé (écriture réservée à SYSTEM et aux administrateurs,
      afin qu'un utilisateur standard ne puisse pas modifier un script exécuté avec les privilèges SYSTEM).
    - Installe ou met à jour winget pour tous les utilisateurs (module Microsoft.WinGet.Client, accès Internet requis) :
      absent d'un Windows 10 fraîchement installé tant que le Microsoft Store n'a pas mis à jour App Installer.
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
$logPath = Join-Path -Path $InstallPath -ChildPath 'Maintenance.log'

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

# --- winget ---------------------------------------------------------------------------------------
# Sur un Windows 10 fraîchement installé, winget est absent tant que le Store n'a pas mis à jour App Installer.
# Microsoft recommande de le provisionner via Repair-WinGetPackageManager -AllUsers, fiable en session administrateur
# (sous SYSTEM, le comportement n'est pas garanti : winget-cli #4271). La maintenance retentera si cette étape échoue.
if ($PSCmdlet.ShouldProcess('winget', 'Installer ou mettre à jour winget pour tous les utilisateurs')) {
    & $targetScript -InstallWingetOnly -LogPath $logPath
    if ($LASTEXITCODE -eq 0) {
        Write-Output 'winget installé et à jour.'
    }
    else {
        Write-Warning "winget ou le runtime Visual C++ n'a pas pu être installé (voir $logPath). La maintenance retentera à chaque exécution."
    }
}

# --- Tâche planifiée ----------------------------------------------------------------------------
function Get-TaskCompatibility {
    <#
        Choisit le niveau de compatibilité de la tâche ("Configurer pour") d'après le système d'exploitation.
        Valeurs TASK_COMPATIBILITY de l'API Planificateur de tâches : 6 = Windows 10 (aussi utilisé par Windows 11
        et Windows Server 2016+), 4 = Windows 8, 3 = Windows 7, 2 = Windows Vista.
        https://learn.microsoft.com/windows/win32/api/taskschd/ne-taskschd-task_compatibility
    #>
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $version = [version]$os.Version

    $compatibility = switch ($true) {
        { $version -ge [version]'10.0' } { @{ Value = 6; Name = 'Windows 10' }; break }
        { $version -ge [version]'6.2' }  { @{ Value = 4; Name = 'Windows 8' }; break }
        { $version -ge [version]'6.1' }  { @{ Value = 3; Name = 'Windows 7' }; break }
        default                          { @{ Value = 2; Name = 'Windows Vista' } }
    }

    [pscustomobject]@{
        Value = $compatibility.Value
        Name  = $compatibility.Name
        OS    = '{0} (build {1})' -f $os.Caption, $os.BuildNumber
    }
}

function Set-TaskCompatibility {
    <#
        Applique le niveau de compatibilité via l'API COM du Planificateur : le cmdlet New-ScheduledTaskSettingsSet
        de Windows PowerShell 5.1 ne propose pas de valeur au-delà de Windows 8.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [Parameter(Mandatory)]
        [int]$Compatibility
    )

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    $definition = $folder.GetTask($TaskName).Definition
    $definition.Settings.Compatibility = $Compatibility
    # 6 = TASK_CREATE_OR_UPDATE ; 5 = TASK_LOGON_SERVICE_ACCOUNT (compte SYSTEM, S-1-5-18).
    [void]$folder.RegisterTaskDefinition($TaskName, $definition, 6, 'S-1-5-18', $null, 5)
}

$compatibility = Get-TaskCompatibility

$powershellExe =Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
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

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "Exécute sfc /scannow puis met à jour les applications avec winget, une par une, en arrière-plan. Journal : $logPath"

if ($PSCmdlet.ShouldProcess($TaskName, 'Enregistrer la tâche planifiée')) {
    try {
        Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -InputObject $task -Force | Out-Null
        Set-TaskCompatibility -TaskName $TaskName -Compatibility $compatibility.Value
        $result = 'OK compatibilité {0} - {1}' -f $compatibility.Name, $compatibility.OS
    }
    catch {
        $result = 'ERREUR {0}' -f $_.Exception.Message
        throw
    }
    finally {
        # Même format que le script de maintenance : une ligne, OK ou ERREUR.
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('{0:dd\/MM\/yyyy HH\:mm\:ss} | {1,-20} | {2}' -f (Get-Date), 'Installation tâche', $result)
    }

    Write-Output ("Tâche '{0}' enregistrée : chaque {1} à {2:HH\:mm}, sous SYSTEM, configurée pour {3} ({4})." -f $TaskName, $DayOfWeek, $At, $compatibility.Name, $compatibility.OS)
    Write-Output ("Journal : {0}" -f $logPath)

    if ($RunNow) {
        Start-ScheduledTask -TaskName $TaskName -TaskPath '\'
        Write-Output 'Tâche démarrée. Le résultat apparaîtra dans le journal à la fin de son exécution.'
    }
}
