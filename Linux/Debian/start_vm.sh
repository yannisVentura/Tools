echo "Enter VM name :"
read vm_name
VBoxManage startvm "$vm_name" --type headless