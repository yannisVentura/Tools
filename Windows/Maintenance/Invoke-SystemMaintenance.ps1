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
        04/11/2026 11:58:10 | Installation winget  | OK
        04/11/2026 11:58:40 | Installation VC++    | OK
        04/11/2026 12:00:02 | sfc /scannow         | OK
        04/11/2026 12:38:47 | winget upgrade --all | ERREUR code -1978335226 (0x8A150006)

.PARAMETER WithDism
    Exécute DISM /Online /Cleanup-Image /RestoreHealth avant SFC (recommandation Microsoft).

.PARAMETER LogPath
    Fichier journal. Par défaut : %ProgramData%\SystemMaintenance\Maintenance.log

.PARAMETER MaxLogLines
    Nombre maximal de lignes conservées dans le journal. Par défaut : 500 (plusieurs années d'historique).

.PARAMETER InstallWingetOnly
    Installe ou répare uniquement winget (module Microsoft.WinGet.Client + Repair-WinGetPackageManager -AllUsers)
    et le runtime Visual C++ nécessaire à winget sous SYSTEM, sans lancer la maintenance.
    Utilisé par Install-MaintenanceTask.ps1, en session administrateur.
    Pendant la maintenance, ces installations sont aussi tentées automatiquement si winget ou le runtime manque.

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
    [int]$MaxLogLines = 500,

    [switch]$InstallWingetOnly
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

    # Une seule ligne par commande, même si un message d'erreur en contient plusieurs.
    $Result = ($Result -replace '\s*[\r\n]+\s*', ' ').Trim()
    $line = '{0:dd\/MM\/yyyy HH\:mm\:ss} | {1,-20} | {2}' -f (Get-Date), $Command, $Result
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

    # Contexte SYSTEM : pas d'alias, on cible directement le paquet App Installer le plus récent contenant winget.exe.
    # Dossier WindowsApps (listable par SYSTEM) + Get-AppxPackage (utile en administrateur, qui ne peut pas toujours lister ce dossier).
    $appsRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps'
    $folders = @(Get-ChildItem -LiteralPath $appsRoot -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName)
    try {
        $folders += @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty InstallLocation)
    }
    catch { }

    $folders | Where-Object { $_ } | Sort-Object -Unique |
        ForEach-Object {
            $version = $null
            $exe = Join-Path -Path $_ -ChildPath 'winget.exe'
            if ([version]::TryParse(((Split-Path -Path $_ -Leaf) -split '_')[1], [ref]$version) -and (Test-Path -LiteralPath $exe)) {
                [pscustomobject]@{ Version = $version; Path = $exe }
            }
        } |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1 -ExpandProperty Path
}

function Install-Winget {
    <#
        Installe ou répare winget pour tous les utilisateurs, selon la méthode Microsoft :
        module PowerShell Microsoft.WinGet.Client + Repair-WinGetPackageManager -AllUsers.
        Sans aucune invite sous Windows PowerShell 5.1 (TLS 1.2, fournisseur NuGet, -Force).
        https://learn.microsoft.com/windows/package-manager/winget/
        https://learn.microsoft.com/powershell/gallery/powershellget/install-on-older-systems
    #>
    # winget est pris en charge à partir de Windows 10 version 1809 (build 17763).
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 17763) {
        throw "winget nécessite Windows 10 version 1809 (build 17763) ou ultérieure ; build actuel : $build"
    }

    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $nuget =Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue |
        Where-Object { $_.Version -ge [version]'2.8.5.201' }
    if (-not $nuget) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope AllUsers -Force | Out-Null
    }

    # -Force : installe la dernière version (même si une ancienne est présente) sans l'invite "dépôt non approuvé".
    Install-Module -Name 'Microsoft.WinGet.Client' -Repository PSGallery -Scope AllUsers -Force -AllowClobber
    Import-Module -Name 'Microsoft.WinGet.Client' -Force

    # Provisionne App Installer (winget + dépendances) pour la machine, dans sa dernière version stable.
    Repair-WinGetPackageManager -AllUsers -Latest -Force | Out-Null

    # Hors SYSTEM : rend winget utilisable tout de suite dans la session de l'administrateur courant.
    # Sur un Windows 10 neuf, l'utilisateur garde l'App Installer d'origine (1.0.x, sans winget) jusqu'à sa prochaine
    # connexion : on lui enregistre explicitement la version la plus récente installée sur la machine.
    # (-RegisterByFamilyName tente de réenregistrer l'ancienne version et échoue avec 0x80073D06.)
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18' -and
        -not (Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue)) {
        try {
            $latest = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' |
                Sort-Object -Property { [version]$_.Version } -Descending |
                Select-Object -First 1
            if ($latest) {
                $manifest = Join-Path -Path $latest.InstallLocation -ChildPath 'AppxManifest.xml'
                Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
            }
        }
        catch { }   # facultatif : la maintenance sous SYSTEM n'en dépend pas
    }
}

function Test-VCRedist {
    # Clé documentée par Microsoft pour détecter le Visual C++ Redistributable 2015-2022.
    # https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files
    $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $key = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$architecture"
    $installed = Get-ItemProperty -LiteralPath $key -Name 'Installed' -ErrorAction SilentlyContinue
    return [bool]($installed -and $installed.Installed -eq 1)
}

function Invoke-VCRedistSetup {
    <#
        Installe silencieusement le Visual C++ Redistributable (lien permanent officiel Microsoft).
        Sans lui, winget.exe lancé sous SYSTEM échoue avec 0xC0000135 (DLL introuvable).
        https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist
        Écrit une ligne de journal et retourne $true en cas de succès.
    #>
    $label = 'Installation VC++'
    $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    # Dossier protégé (pas %TEMP%) : l'exécutable lancé sous SYSTEM ne doit pas pouvoir être remplacé par un utilisateur.
    $installer = Join-Path -Path (Split-Path -Path $LogPath -Parent) -ChildPath "vc_redist.$architecture.exe"

    try {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.$architecture.exe" -OutFile $installer -UseBasicParsing

        # 3010 = redémarrage requis, 1638 = version égale ou supérieure déjà installée.
        $ok = Invoke-Step -Label $label -FilePath $installer -ArgumentList '/install', '/quiet', '/norestart' -SuccessCodes @(0, 3010, 1638)
        return $ok
    }
    catch {
        Write-Log -Command $label -Result ('ERREUR {0}' -f $_.Exception.Message)
        return $false
    }
    finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WingetSetup {
    <#
        Exécute Install-Winget, écrit une ligne de journal et retourne le chemin de winget.exe ($null en cas d'échec).
    #>
    $label = 'Installation winget'
    try {
        Install-Winget
        $path = Get-WingetPath
        if ($path) {
            Write-Log -Command $label -Result 'OK'
            return $path
        }
        Write-Log -Command $label -Result 'ERREUR winget toujours introuvable après installation'
    }
    catch {
        Write-Log -Command $label -Result ('ERREUR {0}' -f $_.Exception.Message)
    }
    return $null
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

if ($InstallWingetOnly) {
    $installed = [bool](Invoke-WingetSetup)
    $runtime = (Test-VCRedist) -or (Invoke-VCRedistSetup)
    Limit-LogSize
    exit [int](-not ($installed -and $runtime))
}

$allOk = $true
$systemDirectory = Get-NativeSystemDirectory

if ($WithDism) {
    $allOk = (Invoke-Step -Label 'DISM /RestoreHealth' -FilePath (Join-Path $systemDirectory 'Dism.exe') `
        -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth', '/NoRestart', '/Quiet') -and $allOk
}

$allOk = (Invoke-Step -Label 'sfc /scannow' -FilePath (Join-Path $systemDirectory 'sfc.exe') -ArgumentList '/scannow') -and $allOk

$wingetPath = Get-WingetPath
if (-not $wingetPath) {
    # Secours : un seul essai de réinstallation (best effort sous SYSTEM, cf. winget-cli #4271).
    $wingetPath = Invoke-WingetSetup
}

if ($wingetPath -and -not (Test-VCRedist)) {
    # winget sous SYSTEM a besoin du runtime Visual C++ (sinon 0xC0000135). Un échec sera visible sur la ligne winget.
    [void](Invoke-VCRedistSetup)
}

if ($wingetPath) {
    $allOk = (Invoke-Step -Label 'winget upgrade --all' -FilePath $wingetPath -WorkingDirectory (Split-Path -Path $wingetPath -Parent) `
        -ArgumentList 'upgrade', '--all', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity' `
        -SuccessCodes $WingetSuccessCodes) -and $allOk
}
else {
    Write-Log -Command 'winget upgrade --all' -Result 'ERREUR winget introuvable'
    $allOk = $false
}

Limit-LogSize

exit [int](-not $allOk)

#endregion
