# About

[![Build status](https://github.com/rgl/s3fs-fuse-windows/workflows/Build/badge.svg)](https://github.com/rgl/s3fs-fuse-windows/actions?query=workflow%3ABuild)

This builds a windows binary artifact of [s3fs-fuse](https://github.com/s3fs-fuse/s3fs-fuse).

Alternative: https://github.com/awslabs/mountpoint-s3

## Usage (in a Windows host)

Download a release, e.g.:

```powershell
# see https://github.com/rgl/s3fs-fuse-windows/releases
$version = "1.97.20270724"
$url = "https://github.com/rgl/s3fs-fuse-windows/releases/download/v$version/s3fs-fuse.zip"
$d = "$PWD\tmp\s3fs-fuse"
$z = "$d\s3fs-fuse.zip"
if (Test-Path $d) {
    Remove-Item -Recurse $d
}
mkdir "$d" | Out-Null
(New-Object Net.WebClient).DownloadFile($url, $z)
Expand-Archive `
    -Path $z `
    -DestinationPath $d
```

In Windows PowerShell, start the s3fs service in foreground:

**NB** You need to replace the credentials and the s3 url. This example targets
the RustFS endpoint that only exists inside the vagrant environment.

```powershell
$env:AWS_ACCESS_KEY_ID = 's3fs-ro'
$env:AWS_SECRET_ACCESS_KEY = 'password'
# NB this can also mount over an existing directory (it automatically manages
#    the mount sub-directory). e.g. c:\s3fs-test.
# NB to debug include:
#       --debug -o dbglevel=debug -o curldbg
&"$d\s3fs.exe" `
    test `
    a: `
    -f `
    -o url=http://localhost:9000 `
    -o tmpdir=c:/windows/temp `
    -o use_path_request_style `
    -o ro `
    -o umask=222 `
    -o compat_dir=1 `
    -o complement_stat=1
```

In another PowerShell Terminal, try listing all the files:

```powershell
Get-ChildItem -Recurse a: | ForEach-Object { $_.FullName } | Sort-Object
```

## Build (in a Ubuntu host)

Install the [windows-2022-uefi-amd64 vagrant box](https://github.com/rgl/windows-vagrant).

Build the `s3fs-fuse.zip` binary artifact:

```bash
vagrant up --no-destroy-on-error --provider=libvirt
ls -laF s3fs-fuse.zip
vagrant destroy -f
```
