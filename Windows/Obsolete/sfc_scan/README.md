The SFC command is a Windows embeded verification tool to check Windows system files integrity.
All of thoses scripts must be launch in a administrator command line.

scranfile.bat call `sfcsfc /scanfile=<file>`. This command scann a file and repare it if necessary.

verifyonly.bat call `sfc /verifyonly`. This command scann Windows file systems ( without modifications or correction). It's goal is to detect errors.

scannow.bat call `sfc /scannow`. This command scann and repare Windows files systems if necessary.