sudo apt-get update && sudo apt-get upgrade;
sudo apt install -y python3;
sudo apt install -y net-tools;
sudo apt install -y git;
sudo apt install -y svn;
sudo apt install -y openssh;
sudo apt install -y openvpn;
sudo apt install -y htop;
sudo add-apt-repository -y "deb https://packages.microsoft.com/repos/vscode stable main" && sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EB3E94ADBE1229CF && sudo apt-get update && sudo apt-get install code;
sudo apt install -y geany && sudo apt install -y geany-plugin*;
sudo apt install -y steam;
mkdir /home/$USER/Documents/projects;
mkdir /home/$USER/Documents/projects/git;
mkdir /home/$USER/Documents/projects/svn;
mkdir /home/$USER/Documents/projects/GoogleDrive;
mkdir /home/$USER/Documents/projects/Master;
echo "Create some aliases..."
echo "alias clone='git clone'" >> /home/$USER/.bash_aliases;
echo "alias upgrade='sudo apt-get update && upgrade'" >> /home/$USER/.bash_aliases;
echo "alias py3='python3'" >> /home/$USER/.bash_aliases;
echo "alias ping1='ping 8.8.8.8'"
cat /home/$USER/.bash_aliases;
