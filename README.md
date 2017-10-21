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


