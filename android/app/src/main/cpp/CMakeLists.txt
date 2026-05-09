cmake_minimum_required(VERSION 3.22.1)

project(essential_android_service LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_WEBUI OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN ON CACHE BOOL "" FORCE)
set(
    GGML_VULKAN_SHADERS_GEN_TOOLCHAIN
    "${CMAKE_CURRENT_SOURCE_DIR}/host-toolchain.cmake"
    CACHE FILEPATH "" FORCE
)

set(ESSENTIAL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../")
set(ESSENTIAL_LLAMA_DIR "${ESSENTIAL_ROOT}/native/runtimes/llama/llama.cpp")
set(ESSENTIAL_INFERENCE_DIR "${ESSENTIAL_ROOT}/native/inference_core")
set(ESSENTIAL_VISION_DIR "${ESSENTIAL_ROOT}/native/runtimes/vision")
set(ESSENTIAL_AUDIO_DIR "${ESSENTIAL_ROOT}/native/runtimes/audio")
set(ESSENTIAL_WHISPER_DIR "${ESSENTIAL_ROOT}/native/third_party/whisper.cpp")
set(ESSENTIAL_VULKAN_HPP_DIR "${ESSENTIAL_ROOT}/third_party/Vulkan-Hpp")
set(ESSENTIAL_SPIRV_HEADERS_DIR "${ESSENTIAL_ROOT}/third_party/SPIRV-Headers/include")

include_directories("${ESSENTIAL_VULKAN_HPP_DIR}")
include_directories("${ESSENTIAL_SPIRV_HEADERS_DIR}")

if(ANDROID AND NOT Vulkan_GLSLC_EXECUTABLE AND EXISTS "${ANDROID_NDK}/shader-tools/darwin-x86_64/glslc")
    set(Vulkan_GLSLC_EXECUTABLE "${ANDROID_NDK}/shader-tools/darwin-x86_64/glslc" CACHE FILEPATH "" FORCE)
endif()

if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(GGML_CPU_ARM_ARCH "armv8.6-a+i8mm+dotprod" CACHE STRING "" FORCE)
endif()

add_subdirectory("${ESSENTIAL_LLAMA_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/llama")
if(EXISTS "${ESSENTIAL_WHISPER_DIR}/CMakeLists.txt")
    set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
    set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
    set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
    set(WHISPER_COREML OFF CACHE BOOL "" FORCE)
    set(WHISPER_OPENVINO OFF CACHE BOOL "" FORCE)
    add_subdirectory("${ESSENTIAL_WHISPER_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/whisper" EXCLUDE_FROM_ALL)
endif()
add_subdirectory("${ESSENTIAL_VISION_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/vision")
add_subdirectory("${ESSENTIAL_AUDIO_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/audio")

add_library(
    essential_android_service
    SHARED
    jni_bridge.cpp
    "${ESSENTIAL_INFERENCE_DIR}/src/essential_llama.cpp"
)

target_include_directories(
    essential_android_service
    PRIVATE
    "${ESSENTIAL_INFERENCE_DIR}/include"
    "${ESSENTIAL_LLAMA_DIR}/include"
    "${ESSENTIAL_AUDIO_DIR}/include"
)

target_link_libraries(
    essential_android_service
    PRIVATE
    llama
    essential_vision
    essential_audio
    android
    log
)

target_compile_definitions(
    essential_android_service
    PRIVATE
    ESSENTIAL_LLAMA_PERF_LOGS=1
)
