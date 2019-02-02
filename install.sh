#!/usr/bin/sh

# update our externals/dependencies
git submodule update --recursive --init

# install cimgui
cd external/cimgui/
make -j$(nproc)
sudo cp cimgui.so /usr/bin/libcimgui.so

# add neobc and dtoavk-bindings to dub environment
cd ../neobc
dub add-local .
cd ../dtoavk-bindings
dub add-local .

# go back to project root
cd ../../
echo "Should be able to build, try `dub build --compiler=dmd --build=release`"
