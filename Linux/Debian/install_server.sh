#Login as root
sudo su

# Default packages
sudo apt-get update && sudo apt-get upgrade;
sudo apt install -y python3;
sudo apt install -y net-tools;
sudo apt install -y git;
sudo apt install -y svn;
sudo apt install -y openssh;
sudo apt install -y openvpn;
sudo apt install -y htop;

# Server software
sudo apt install -y jenkins;
sudo apt install -y docker;
sudo apt install virtualbox;    