# For a given Zip file extract it to a destination folder
# Example : .\UnzipFile.PS1 C:\test\tested.zip C:\MyToolBox\test

$archive=$args[0]
$dest=$args[1]
[Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
[IO.Compression.ZipFile]::ExtractToDirectory($archive, $dest)