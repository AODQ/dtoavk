# dtoavk

To summarize this project in a few points:
  - glTF2.0 viewer
  - Rendering backend using Vulkan-RTX
  - Real time and offline Global Illumination
  - (possibly) Virtual Reality support
  - Written in D BetterC (aka, no garbage collector, no D standard library)

The idea is to remain as a rendering-backend only (hence why BetterC is used ->
  good support for bindings with other language, no garbage collector)
