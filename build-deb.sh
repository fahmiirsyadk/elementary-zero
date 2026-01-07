#!/bin/bash

set -e

VERSION="1.0.0"
PACKAGE_NAME="elementary-zero"
BUILD_DIR="/tmp/${PACKAGE_NAME}-build"
DEBIAN_DIR="${BUILD_DIR}/DEBIAN"

echo "Building ${PACKAGE_NAME} ${VERSION}..."

rm -rf ${BUILD_DIR}
mkdir -p ${DEBIAN_DIR}

meson setup build --prefix=/usr
ninja -C build

DESTDIR=${BUILD_DIR} ninja -C build install

cat > ${DEBIAN_DIR}/control <<EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: amd64
Maintainer: fahmiirsyadk <fahmiirsyadk@github.com>
Depends: git, meson, ninja-build, policykit-1, libgranite-7-0, libgtk-4-1, libgee-0.8-2, libjson-glib-1.0-0, libsoup-3.0-0
Description: Package patcher for elementary OS
 Graphical application for managing and applying patches to elementary OS packages.
Priority: optional
Section: utils
EOF

dpkg-deb --build ${BUILD_DIR} ${PACKAGE_NAME}_${VERSION}_amd64.deb

echo "Package created: ${PACKAGE_NAME}_${VERSION}_amd64.deb"
echo "Upload this file to GitHub releases."

