#Requires -Version 5.1
<#
.SYNOPSIS
    Maintenance silencieuse du poste : vérification des fichiers système (SFC) puis mise à jour des applications (winget).

.DESCRIPTION
    Conçu pour être exécuté par une tâche planifiée sous le compte SYSTEM :
    aucune fenêtre, aucune pop-up, aucune validation demandée à l'utilisateur.

    Journal volontairement minimal : une ligne par commande, et pour winget une ligne par application mise à jour,
    OK ou ERREUR avec le code retour. Un échec sur une application n'empêche pas la mise à jour des autres.
    Un seul fichier, plafonné à MaxLogLines lignes (les plus anciennes sont supprimées).

    Exemple de journal :
        04/11/2026 12:00:02 | sfc /scannow         | OK
        04/11/2026 12:01:15 | winget upgrade       | OK Audacity.Audacity 3.7.9 -> 4.0.1
        04/11/2026 12:01:40 | winget upgrade       | ERREUR EPSON.EpsonNetPrint 3.1.4.0 -> 3.3.1 : code -2145844844 (0x80190194)

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
    Codes de sortie du script (résultat de la tâche planifiée) :
      0 = maintenance exécutée. Des applications peuvent être en ERREUR dans le journal : elles sont à mettre à jour
          manuellement, mais ne font pas échouer la tâche tant qu'au moins une autre a réussi (objectif : un poste
          globalement maintenu).
      1 = échec de SFC ou DISM, winget introuvable ou non exécutable (liste des mises à jour impossible à obtenir),
          ou échec de toutes les applications à mettre à jour.
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
    # On cible en priorité le winget.exe réel du paquet App Installer le plus récent, et non l'alias d'exécution du PATH :
    # cet alias (%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe) est un point d'analyse propre à un utilisateur.
    # Si le PATH de SYSTEM contient le dossier WindowsApps d'un utilisateur, SYSTEM trouve cet alias mais ne peut pas l'exécuter
    # ("Le système ne peut pas accéder au fichier").
    $packagePath = Get-WingetPackagePath
    if ($packagePath) {
        return $packagePath
    }

    # Dernier recours, hors SYSTEM uniquement : l'alias d'exécution de l'utilisateur courant.
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Source
    }
}

function Get-WingetPackagePath {
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

        [string]$WorkingDirectory = $env:SystemRoot,

        # Précision ajoutée au résultat (ex. "Audacity.Audacity 3.7.9 -> 4.0.1").
        [string]$Detail
    )

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory `
            -WindowStyle Hidden -Wait -PassThru
        $code = $process.ExitCode

        if ($SuccessCodes -contains $code) {
            Write-Log -Command $Label -Result ('OK {0}' -f $Detail)
            return $true
        }

        if ($Detail) {
            Write-Log -Command $Label -Result ('ERREUR {0} : code {1} (0x{2:X8})' -f $Detail, $code, $code)
        }
        else {
            Write-Log -Command $Label -Result (Format-Error $code)
        }
        return $false
    }
    catch {
        Write-Log -Command $Label -Result (('ERREUR {0} lancement impossible : {1}' -f $Detail, $_.Exception.Message) -replace '\s+', ' ')
        return $false
    }
}

function Invoke-WingetCapture {
    <#
        Exécute winget sans fenêtre et retourne son code de sortie et sa sortie texte (une entrée par ligne).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WingetPath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    # En PowerShell 5.1, '2>&1' + ErrorActionPreference 'Stop' transforme la moindre ligne stderr en erreur bloquante.
    $ErrorActionPreference = 'Continue'

    $previousEncoding = $null
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.Encoding]::UTF8   # winget écrit en UTF-8
    }
    catch { }

    Push-Location -LiteralPath (Split-Path -Path $WingetPath -Parent)
    try {
        # Les indicateurs de progression réécrivent la ligne via '\r' : on ne garde que le dernier état.
        $lines = @(& $WingetPath @ArgumentList 2>&1 | ForEach-Object { ($_.ToString() -split "`r")[-1] })
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines }
    }
    finally {
        Pop-Location
        if ($previousEncoding) {
            try { [Console]::OutputEncoding = $previousEncoding } catch { }
        }
    }
}

function ConvertFrom-WingetTable {
    <#
        Extrait le premier tableau de "winget upgrade" : une entrée par application (Id, Version, Available).
        Les colonnes sont repérées par la position des titres de l'en-tête (Nom/Name, ID, Version, Disponible/Available, Source),
        ce qui fonctionne quelle que soit la langue. Les tableaux suivants (applications épinglées ou nécessitant un ciblage
        explicite) sont ignorés. Retourne un tableau vide s'il n'y a aucun tableau (aucune mise à jour).
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$Lines = @()
    )

    $separator = -1
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^-{10,}\s*$') {
            $separator = $i
            break
        }
    }
    if ($separator -lt 0) {
        return @()
    }

    $columns = [regex]::Matches($Lines[$separator - 1], '\S+')
    if ($columns.Count -lt 4) {
        throw "en-tête du tableau winget non reconnu : '$($Lines[$separator - 1].Trim())'"
    }
    $idStart = $columns[1].Index
    $versionStart = $columns[2].Index
    $availableStart = $columns[3].Index
    $availableEnd = if ($columns.Count -ge 5) { $columns[4].Index } else { [int]::MaxValue }

    $cell = {
        param([string]$Line, [int]$Start, [int]$End)
        if ($Line.Length -le $Start) { return '' }
        $Line.Substring($Start, [Math]::Min($End, $Line.Length) - $Start).Trim()
    }

    for ($i = $separator + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line.Trim().Length -eq 0 -or $line.Length -le $availableStart) {
            break   # fin du tableau (ligne vide ou ligne de synthèse "N mises à niveau disponibles")
        }

        $id = & $cell $line $idStart $versionStart
        $available = & $cell $line $availableStart $availableEnd
        if ($id -notmatch '^\S+$' -or -not $available) {
            break
        }

        [pscustomobject]@{
            Id        = $id
            Version   = & $cell $line $versionStart $availableStart
            Available = $available
        }
    }
}

function Invoke-WingetUpgrade {
    <#
        Met à jour les applications une par une et écrit une ligne de journal par application :
        un échec isolé n'empêche pas les autres mises à jour et reste identifiable dans le journal.
        Retourne $true s'il n'y a aucune mise à jour ou si au moins une application a été mise à jour, même si d'autres
        échouent ; $false si la liste n'a pas pu être obtenue (winget non exécutable) ou si toutes les applications ont échoué.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WingetPath
    )

    $label = 'winget upgrade'

    try {
        $list = Invoke-WingetCapture -WingetPath $WingetPath -ArgumentList 'upgrade', '--accept-source-agreements', '--disable-interactivity'
        if ($WingetSuccessCodes -notcontains $list.ExitCode) {
            Write-Log -Command $label -Result ('ERREUR liste des mises à jour : code {0} (0x{0:X8})' -f $list.ExitCode)
            return $false
        }
        $packages = @(ConvertFrom-WingetTable -Lines $list.Lines)
    }
    catch {
        # Première ligne seulement : PowerShell ajoute la position dans le script ("Au caractère ...").
        Write-Log -Command $label -Result ('ERREUR liste des mises à jour : {0}' -f ($_.Exception.Message -split '[\r\n]')[0])
        return $false
    }

    if ($packages.Count -eq 0) {
        Write-Log -Command $label -Result 'OK aucune mise à jour disponible'
        return $true
    }

    $succeeded = 0
    foreach ($package in $packages) {
        if ($package.Id -match '(…|\.\.\.)$') {
            Write-Log -Command $label -Result ('ERREUR {0} : identifiant tronqué' -f $package.Id)
            continue
        }

        $detail = '{0} {1} -> {2}' -f $package.Id, $package.Version, $package.Available
        if (Invoke-Step -Label $label -Detail $detail -FilePath $WingetPath -WorkingDirectory (Split-Path -Path $WingetPath -Parent) `
                -ArgumentList 'upgrade', '--id', $package.Id, '--exact', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity' `
                -SuccessCodes $WingetSuccessCodes) {
            $succeeded++
        }
    }

    # Objectif : maintenir le poste "globalement" à jour. Des échecs isolés restent visibles dans le journal sans faire
    # échouer la tâche ; en revanche, si aucune application n'a pu être mise à jour, l'exécution est un échec.
    return ($succeeded -gt 0)
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
    $allOk = (Invoke-WingetUpgrade -WingetPath $wingetPath) -and $allOk
}
else {
    Write-Log -Command 'winget upgrade' -Result 'ERREUR winget introuvable'
    $allOk = $false
}

Limit-LogSize

exit [int](-not $allOk)

#endregion
