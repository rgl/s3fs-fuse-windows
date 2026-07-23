Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Write-Output (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    Exit 1
}

# install dependencies.
choco install --no-progress -y nssm carbon
if ($LASTEXITCODE) {
    throw "bash execution failed with exit code $LASTEXITCODE (0x$($LASTEXITCODE.ToString('X8')))"
}

# install the rustfs s3 server.
$serviceName = 'rustfs'
$serviceUsername = "NT SERVICE\$serviceName"
$serviceHome = "C:\$serviceName"
$serviceLogsHome = "$serviceHome\logs"
$serviceDataHome = "$serviceHome\data"
$rustfs = "$serviceHome\bin\rustfs.exe"
$rc = "$serviceHome\bin\rc.exe"
Write-Host "Creating the $serviceName service..."
nssm install $serviceName $rustfs
nssm set $serviceName AppParameters `
    --address :9000 `
    --console-address :9001 `
    --console-enable `
    $serviceDataHome
nssm set $serviceName AppEnvironmentExtra `
    RUST_LOG=warn `
    RUSTFS_ACCESS_KEY=admin `
    RUSTFS_SECRET_KEY=admin
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppRotateFiles 1
nssm set $serviceName AppRotateOnline 1
nssm set $serviceName AppRotateSeconds 86400
nssm set $serviceName AppRotateBytes 1048576
nssm set $serviceName AppStdout "$serviceHome\logs\$serviceName-stdout.log"
nssm set $serviceName AppStderr "$serviceHome\logs\$serviceName-stderr.log"
$result = sc.exe sidtype $serviceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
$result = sc.exe config $serviceName obj= $serviceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
$result = sc.exe failure $serviceName reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}
@(
    $serviceLogsHome
    $serviceDataHome
) | ForEach-Object {
    mkdir $_ -Force | Out-Null
    Disable-CAclInheritance $_
    Grant-CPermission $_ $serviceUsername FullControl
    Grant-CPermission $_ Administrators FullControl
    Grant-CPermission $_ $env:USERNAME FullControl
}
# see https://github.com/rustfs/rustfs/releases
$archiveVersion = '1.0.0-beta.11'
$archiveUrl = "https://github.com/rustfs/rustfs/releases/download/$archiveVersion/rustfs-windows-x86_64-v$archiveVersion.zip"
$archivePath = "$env:TEMP\$(Split-Path -Leaf $archiveUrl)"
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
mkdir "$serviceHome\bin" -Force | Out-Null
Expand-Archive $archivePath -DestinationPath "$serviceHome\bin"
Remove-Item $archivePath
# see https://github.com/rustfs/cli/releases
$archiveVersion = '0.1.29'
$archiveUrl = "https://github.com/rustfs/cli/releases/download/v$archiveVersion/rustfs-cli-windows-amd64-v$archiveVersion.zip"
$archivePath = "$env:TEMP\$(Split-Path -Leaf $archiveUrl)"
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
Expand-Archive $archivePath -DestinationPath "$serviceHome\bin"
Remove-Item $archivePath
Start-Service $serviceName
&$rc alias set local http://localhost:9000 admin admin
&$rc admin info server local
&$rc mb local/test
# allow anonymous access to bucket content.
# e.g. to http://localhost:9000/test/index.html
&$rc anonymous set download local/test
Set-Content -Encoding ascii -Path "$env:TEMP\index.html" -Value @"
<!doctype html>
<html>
<head><title>Hello, World!</title></head>
<body>Hello, World!</body>
</html>
"@
&$rc cp "$env:TEMP\index.html" local/test/
&$rc stat local/test/index.html
&$rc tag set --tags example-tag=example-value -- local/test/index.html
&$rc tag list local/test/index.html
&$rc ls local/test
Set-Content -Encoding ascii -Path "$env:TEMP\rustfs-policy-s3fs-ro.json" -Value @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::*"
      ],
      "Condition": {}
    }
  ]
}
"@
&$rc admin policy create local s3fs-ro "$env:TEMP\rustfs-policy-s3fs-ro.json"
&$rc admin user add local s3fs-ro password
&$rc admin policy attach local s3fs-ro --user s3fs-ro
[IO.File]::WriteAllText(
    "$env:USERPROFILE\Desktop\RustFS.url",
    @"
[InternetShortcut]
URL=http://localhost:9000
"@)
[IO.File]::WriteAllText(
    "$env:USERPROFILE\Desktop\RustFS Test Index.url",
    @"
[InternetShortcut]
URL=http://localhost:9000/test/index.html
"@)
[IO.File]::WriteAllText(
    "$env:USERPROFILE\Desktop\RustFS Console.url",
    @"
[InternetShortcut]
URL=http://localhost:9001
"@)

# install s3fs-fuse.
$z = if (Test-Path /vagrant/s3fs-fuse.zip) {
    "/vagrant/s3fs-fuse.zip"
} else {
    Resolve-Path "s3fs-fuse.zip"
}
$d = "c:\s3fs-fuse"
if (Test-Path $d) {
    Remove-Item -Recurse $d
}
mkdir $d | Out-Null
Expand-Archive `
    -Path $z `
    -DestinationPath $d

# test.
$s3fs = "$d\s3fs.exe"
&$s3fs --version

# start a service to mount the test bucket.
# NB maybe its better to use https://winfsp.dev/doc/WinFsp-Service-Architecture/?
$serviceName = 's3fs-test'
$serviceUsername = "NT SERVICE\$serviceName"
$serviceHome = "C:\$serviceName"
$serviceLogsHome = "$serviceHome\logs"
Write-Host "Creating the $serviceName service..."
nssm install $serviceName $s3fs
nssm set $serviceName AppParameters `
    test `
    t: `
    -f `
    -o url=http://localhost:9000 `
    -o tmpdir=c:/windows/temp `
    -o use_path_request_style `
    -o ro `
    -o umask=222 `
    -o compat_dir=1 `
    -o complement_stat=1
nssm set $serviceName AppEnvironmentExtra `
    AWS_ACCESS_KEY_ID=s3fs-ro `
    AWS_SECRET_ACCESS_KEY=password
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppRotateFiles 1
nssm set $serviceName AppRotateOnline 1
nssm set $serviceName AppRotateSeconds 86400
nssm set $serviceName AppRotateBytes 1048576
nssm set $serviceName AppStdout "$serviceHome\logs\$serviceName-stdout.log"
nssm set $serviceName AppStderr "$serviceHome\logs\$serviceName-stderr.log"
$result = sc.exe sidtype $serviceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
$result = sc.exe config $serviceName obj= $serviceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
$result = sc.exe failure $serviceName reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}
@(
    $serviceLogsHome
) | ForEach-Object {
    mkdir $_ -Force | Out-Null
    Disable-CAclInheritance $_
    Grant-CPermission $_ $serviceUsername FullControl
    Grant-CPermission $_ Administrators FullControl
    Grant-CPermission $_ $env:USERNAME FullControl
}
Write-Host "Starting the $serviceName service..."
Start-Service $serviceName

Write-Host "Listing all the files in t:..."
Get-ChildItem -Recurse t: | ForEach-Object { $_.FullName } | Sort-Object
