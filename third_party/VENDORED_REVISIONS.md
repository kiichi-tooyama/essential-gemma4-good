# Vendored revisions

This repository vendors selected upstream sources directly so the initial
project commit can be restored without nested Git metadata.

| Path | Upstream | Revision |
| --- | --- | --- |
| `native/runtimes/llama/llama.cpp` | `https://github.com/ggml-org/llama.cpp.git` | `b760272` plus local Vulkan edits |
| `third_party/SPIRV-Headers` | `https://github.com/KhronosGroup/SPIRV-Headers.git` | `ad9184e` |
| `third_party/Vulkan-Hpp` | `https://github.com/KhronosGroup/Vulkan-Hpp.git` | `1a24b01` |
