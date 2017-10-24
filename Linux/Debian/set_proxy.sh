echo "Please enter your http proxy:"
read http_proxy
echo "Please enter your https proxy:"
read https_proxy
echo "Please wait..."
echo "Set proxy to environment..."

echo "Backup previous conf..."
$date=$(date +%D)

sudo cp /etc/environment /etc/environment_back
cat /etc/environment_back
sudo echo 'export http_proxy="$http_proxy"' >> /etc/environment
sudo echo 'export https_proxy="$https_proxy"' >> /etc/environment
cat /etc/environment

echo "set proxy to apt.."
sudo cp /etc/apt/apt.conf /etc/apt/apt_back.conf
cat /etc/apt/apt_back.conf
sudo echo 'Acquire::http::proxy "$http_proxy"' >> /etc/apt/apt.conf
sudo echo 'Acquire::http::proxy "$https_proxy"' >> /etc/apt/apt.conf
cat /etc/apt/apt.conf

echo "set proxy to wget..."
sudo cp /etc/wgetrc /etc/wgetrc_back
cat /etc/wgetrc_back
sudo echo "http_proxy = $http_proxy" >> /etc/wgetrc
sudo echo "https_proxy = $https_proxy" >> /etc/wgetrc
cat /etc/wgetrc