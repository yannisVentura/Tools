sudo su

echo "Please enter your http proxy:"
read http_proxy
echo "Please enter your https proxy:"
read https_proxy
echo "Please wait..."
echo "Set proxy to environment..."

echo "Backup previous conf..."

sudo cp /etc/environment /etc/environment_back
cat /etc/environment_back
sudo echo 'http_proxy="$http_proxy"' >> /etc/environment
sudo echo 'https_proxy="$https_proxy"' >> /etc/environment
cat /etc/environments