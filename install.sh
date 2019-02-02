#!/usr/bin/sh

# Can use this script to install dependencies and dub dependencies to your local
#   project repository. This has only been tested on Linux.

echo " -- Updating dtoavk external dependencies"
git submodule update --recursive --init

echo " -- Installing cimgui for local project repository"
cd external/cimgui/
make -j$(nproc)
echo " -- Attempt move of cimgui.so to local project repository"
mv cimgui.so ../../libcimgui.so

echo " -- Adding neobc and dtoavk-bindings to dub environment"
cd ../neobc
dub add-local .
cd ../dtoavk-bindings
dub add-local .

cd ../../
echo " -- Should be able to build, try: dub build --compiler=dmd --build=release"
