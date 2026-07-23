#!/usr/bin/bash
set -eux

# see https://github.com/s3fs-fuse/s3fs-fuse/releases
S3FS_VERSION="v1.97"

# install the winfsp dependency.
# see https://github.com/winfsp/winfsp/releases/tag/v2.1
# see https://community.chocolatey.org/packages/winfsp
choco install --no-progress -y winfsp --version 2.1.25156

# install dependencies.
pacman --noconfirm --needed -Sy \
    autoconf \
    automake \
    gcc \
    libcurl-devel \
    libxml2-devel \
    libzstd-devel \
    make \
    openssl-devel \
    pkg-config \
    zip

# download the source-code.
if [ "${CI:-}" != "true" ]; then
    cd ~
fi
rm -rf s3fs-fuse
git clone --branch "$S3FS_VERSION" --depth 1 https://github.com/s3fs-fuse/s3fs-fuse
pushd s3fs-fuse

# create the fuse3 pkg-config definition.
cp -r "/c/Program Files (x86)/WinFsp" WinFsp
# see https://github.com/winfsp/winfsp/blob/v2.1/src/dll/fuse3/fuse3.pc.in
cat > ./fuse3.pc << 'EOS'
arch=x64
prefix=${pcfiledir}/WinFsp
incdir=${prefix}/inc/fuse3
implib=${prefix}/bin/winfsp-${arch}.dll

Name: fuse3
Description: WinFsp FUSE3 compatible API
Version: 3.2
URL: https://github.com/winfsp/winfsp
Libs: "${implib}"
Cflags: -I"${incdir}"
EOS

# build.
# see https://github.com/s3fs-fuse/s3fs-fuse/blob/master/COMPILATION.md#compilation-on-windows-using-msys2
./autogen.sh
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:$(pwd)" ./configure
make CXXFLAGS="-I/usr/include"

# package.
rm -rf bin
mkdir bin
cp -a ./src/s3fs.exe bin
cp -a ./WinFsp/bin/winfsp-x64.dll bin
cp -a /usr/bin/msys-*.dll bin
deps="$(ldd ./bin/s3fs.exe | grep s3fs-fuse/bin/ | awk '{print $1}')"
(cd bin && rm -f ../../s3fs-fuse.zip && zip -9 ../../s3fs-fuse.zip s3fs.exe $deps)
popd
unzip -l s3fs-fuse.zip
sha256sum s3fs-fuse.zip

# copy to the vagrant host.
if [ -d /c/vagrant ]; then
    install s3fs-fuse.zip /c/vagrant
fi
