# dtoavk

To summarize this project in a few points:
  - glTF2.0 viewer
  - Rendering backend using Vulkan-RTX
  - Real time and offline Global Illumination
  - (possibly) Virtual Reality support
  - Written in D BetterC (aka, no garbage collector, no D standard library)

The idea is to remain as a rendering-backend only. 

Why BetterC ?
  The only stuff I want from D is its templates, metaprograming,
    static-introspection, mixins, modules, DUB, fast compile times, and uniform
    function call syntax, all features that are completely missing from any
    other language. I don't want the garbage collector, and I don't want the D
    runtime:

  Since this is a real-time rendering backend, and nothing more, none of the
    code should be written with a GC.

  By removing the D runtime, the language becomes a lot simpler to use/bind with
    other languages. languages. In terms of graphics programming, C, C++ and
    Rust are much more attractive than D.

  Unfortunately, the downside is that the standard library has to be completely
    omitted until the standard library works completely with @nogc, and BetterC
    has some mechanism to support exceptions. Neither of these are going to
    happen any time soon. Thus, the entire D standard library is omitted.
