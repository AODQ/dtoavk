# dtoavk

To summarize this project in a few points:
  - glTF2.0 viewer
  - Rendering backend using Vulkan-RTX
  - Real time and offline Global Illumination
  - (possibly) Virtual Reality support
  - Written in D BetterC (aka, no garbage collector, no D standard library)

The idea is to remain as a rendering-backend only (hence why BetterC is used ->
  good support for bindings with other language, no garbage collector)

Supported platforms (currently):
  - Linux + Vulkan

Supported compilers:
  - DMD
Hopefully will target LDC in the future, but LDC and GDC both seem to have
  abysmal BetterC support


# Installation

- LINUX:

  Prequisites:
    - Must have either DMD or LDC installed
    - Must have DUB installed

  Instructions:
  ```
    git clone https://github.com/AODQ/dtoavk
    cd dtoavk
    chmod +x install.sh
    ./install.sh
    dub build --compiler=dmd --build=release
  ```
