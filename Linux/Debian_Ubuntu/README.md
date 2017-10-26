# Debian

This folder contain scripts currently support and tested on Debian / Ubuntu / Linux Mint Operating systems.

## set_env
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

## set_python_env

This script goal is to provide a default python installation using `pip install`. I use it when I have to quick install Python and Django to another computer.


## start_vm

The start vm script is designed to start a specific virtual machine using virtual box.
For a given virtual machine name the script launch and start the VM.

## set_proxy

For a given http and an https proxy this script automatically edit `/etc/environment` to set the proxy configuration.

This script must work for other Linux OS (like Red Hat or CentOS ) but it don't be tested yet.