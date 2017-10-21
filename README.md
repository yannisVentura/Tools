# Scripting tools

This project contain some of my scripts for Windows and Linux ( Debian ) based os.

## Windows

## Activate Powershell script on your computer

To activate Powershell Script on you computer open Powershell as an administrator and enter the following command :

    `Set-ExecutionPolicy RemoteSigned`


## ZipFile

This Powershell script allow users to Zip and Unzip Files with the Microsoft Windows functionnality. It's usefull because without install anything if you are running Windows 7 / 8 / 8.1 /10 /Server 2008 R2 / Server 2012 you can use it without install another utilisty like winrar.

To run the script open a powershell terminal in /Tools/Windows and call the script :

    `./ZipFile.PS1 <source> <destination>`
    
The <source> path is the path to the folder you need to compres and the destination is the destination you woul like to put it.

Then script will asked about a file name for the archive.

## UnzipFile

The UnzipFile script is also a Powershell script.

    `.\UnzipFile.PS1 <zippedFile> <destination>`

For a given file and a destination it will extract the archive to it.

## changeKey

This PowerShell script allow users to change easly their Microsoft Windows activation key.
Be sure to execute this script as an administrator.

    `./changeKey.PS1`

## Linux

## Set_env

The set env script update the system and install some Debian Packages for developper. By executing this script the following packages will be installed : 

_ Python3
_ net-tools
_ git
_ svn
_ openssh
_ openvpn
_ htop
_ dropbox
_ geany ( text editor )
_ visual studio code

It will also create some folders to manage your developement in the $USER/Documents folder : 

    /home/$USER/Documents/projects
    /home/$USER/Documents/projects/git
    /home/$USER/Documents/projects/svn
    /home/$USER/Documents/projects/GoogleDrive
    /home/$USER/Documents/projects/Master

Finally it create some aliases in the /bash_aliases file.

    clone='git clone
    upgrade='sudo apt-get update && upgrade'
    py3='python3
    ping1='ping 8.8.8.8'


