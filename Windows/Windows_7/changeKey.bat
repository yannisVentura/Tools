echo " You are about to change your windows activation key, please be sure to execute this script as an Administrator...\n Are you sure about that ? ( y = yes  n = no) "
read answer
if [ $answer -ne "y" ]
    then
        echo "A clever person solves a problem. \n A wise person avoids it. \n -- Einstein"
else
    echo "enter your activation key :"
    read key
    slmgr -ipk $key
    slmgr -acto
fi