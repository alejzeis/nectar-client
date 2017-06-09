#!/bin/sh

NECTAR_CLIENT_VERSION=1.4.6-alpha2
NECTAR_CLIENT_EXECUTABLE=nectar-client
BUILD_NUMBER=0
BUILD_ARCH=$(uname -m)

if [ $# == 0 ]; then
    BUILD_NUMBER=1
else
    BUILD_NUMBER=$1
fi

if [ $# == 2 ]; then
    BUILD_ARCH=$2
else
    BUILD_ARCH=x86_64
fi

# Build Deb
fpm -s dir -t deb -a $BUILD_ARCH -d xdelta3 -d libjwt0 -n nectar-client -v $NECTAR_CLIENT_VERSION --iteration $BUILD_NUMBER --after-install nectar-client-install.sh nectar-client-service=/usr/bin/nectar-client-service ../bin/nectar-client=/usr/bin/nectar-client nectar-client.service=/usr/lib/systemd/system/nectar-client.service
# Build RPM
fpm -s dir -t rpm -a $BUILD_ARCH -d xdelta -d libjwt -n nectar-client -v $NECTAR_CLIENT_VERSION --iteration $BUILD_NUMBER --after-install nectar-client-install.sh nectar-client-service=/usr/bin/nectar-client-service ../bin/nectar-client=/usr/bin/nectar-client nectar-client.service=/usr/lib/systemd/system/nectar-client.service
