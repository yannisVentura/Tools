REM The sfc command above is used to scan <file> and then repair it if an issue is found.
REM example : sfc /scanfile=c:\windows\system32\ieframe.dll
set /p file="Enter path files (example : c:\windows\system32\ieframe.dll) :"
sfc /scanfile=%file%