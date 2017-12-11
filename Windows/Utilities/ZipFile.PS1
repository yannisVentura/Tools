# For a given source and a destination create a ZipFile.
# Example : .\ZipFiles.PS1 C:\test C:\archives\test
$sourceFolder = $args[0]
$zip_name=Read-Host "Please enter the archive name"
$zip_file=$zip_name+".zip"
$destinationZip = $args[1]+"\"+$zip_file
[Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
[System.IO.Compression.ZipFile]::CreateFromDirectory($sourceFolder, $destinationZip)