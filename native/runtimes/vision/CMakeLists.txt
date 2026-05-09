cmake_minimum_required(VERSION 3.22.1)

project(essential_vision LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(ESSENTIAL_VISION_ENABLE_MEDIAPIPE "Build MediaPipe vision backend" OFF)
option(ESSENTIAL_VISION_ENABLE_ONNX "Build ONNX Runtime vision backend" ON)

add_library(essential_vision SHARED)

target_include_directories(
  essential_vision
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(ESSENTIAL_VISION_ENABLE_MEDIAPIPE)
  target_sources(essential_vision PRIVATE src/essential_vision_mediapipe.cpp)
  find_package(OpenCV QUIET)
  if(OpenCV_FOUND)
    target_link_libraries(essential_vision PRIVATE ${OpenCV_LIBS})
  endif()
else()
  target_compile_definitions(essential_vision PRIVATE ESSENTIAL_VISION_STANDALONE_ONNX=1)
endif()

if(ESSENTIAL_VISION_ENABLE_ONNX)
  find_path(ONNXRUNTIME_INCLUDE_DIR onnxruntime_c_api.h)
  find_library(ONNXRUNTIME_LIBRARY onnxruntime)
  if(ONNXRUNTIME_INCLUDE_DIR)
    target_sources(essential_vision PRIVATE src/essential_vision_onnx.cpp)
    target_include_directories(essential_vision PRIVATE "${ONNXRUNTIME_INCLUDE_DIR}")
  else()
    target_sources(essential_vision PRIVATE src/essential_vision_stub.cpp)
  endif()
  if(ONNXRUNTIME_LIBRARY)
    target_link_libraries(essential_vision PRIVATE "${ONNXRUNTIME_LIBRARY}")
  endif()
endif()

if(ANDROID)
  target_link_libraries(essential_vision PRIVATE android log)
endif()
