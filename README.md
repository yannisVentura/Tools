# Scripting tools

This project contain some of my scripts for Windows and Linux ( Debian ) based os.

## Windows

### Activate Powershell script on your computer

/!\ 
To activate Powershell Script on you computer open Powershell as an administrator and enter the following command :

    `Set-ExecutionPolicy RemoteSigned`
/!\ 

### Maintenance

Silent weekly maintenance for Windows 10/11: `sfc /scannow` then winget updates, application by application, run by a scheduled task under SYSTEM, with a capped log (one line per command and per application).
See [Windows/Maintenance/README.md](Windows/Maintenance/README.md).

### Obsolete

Older Windows scripts (2017: Windows 7 product key, SFC shortcuts, Python/Django setup, Zip utilities) are legacy code kept for history in [Windows/Obsolete](Windows/Obsolete/README.md), with their modern replacements.

## Linux

### Debian scripts

I principally use Debian based distributions like Ubuntu or Linux Mint so I decided to regroup somes scripts I currently used.

