#!/usr/bin/sh

# update our externals/dependencies
git submodule update --recursive --init

# install cimgui
cd external/cimgui/
make -j$(nproc)
echo "Installing cimgui.so to local project repository"
cp cimgui.so /../../libcimgui.so

# add neobc and dtoavk-bindings to dub environment
cd ../neobc
dub add-local .
cd ../dtoavk-bindings
dub add-local .

# go back to project root
cd ../../
echo "Should be able to build, try `dub build --compiler=dmd --build=release`"
