# Afficher graphiquement une variable avant de cliquer sur continue ( exemple j'affiche la clé d'activation avant de l'exécuter)
echo "You are about to change your windows 7 activation key, please be sure you are running this script as an Administrator ..."
$response=Read-Host "Would you like to change your windows 7  key ?"

if ($response -eq "yes") || ($response -eq "y")
{
    $key=Read-Host "Please enter your Key"
    $shell = new-object -com wscript.shell
    $shell.popup("Your new Windows 7 Key is : $key")
    slmgr -ipk $key
    slmgr -acto
}
else
    echo "Take a time to think about it little padawan."