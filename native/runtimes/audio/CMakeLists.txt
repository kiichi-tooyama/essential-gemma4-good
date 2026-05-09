cmake_minimum_required(VERSION 3.22.1)

project(essential_audio LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(
  essential_audio
  SHARED
  src/essential_audio_whisper.cpp
  src/essential_audio_tts.cpp
)

target_include_directories(
  essential_audio
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

if(TARGET whisper)
  target_link_libraries(essential_audio PRIVATE whisper)
else()
  find_path(WHISPER_INCLUDE_DIR whisper.h)
  find_library(WHISPER_LIBRARY whisper)
  if(WHISPER_INCLUDE_DIR)
    target_include_directories(essential_audio PRIVATE "${WHISPER_INCLUDE_DIR}")
  endif()
  if(WHISPER_LIBRARY)
    target_link_libraries(essential_audio PRIVATE "${WHISPER_LIBRARY}")
  endif()
endif()

find_path(ONNXRUNTIME_INCLUDE_DIR onnxruntime_c_api.h)
find_library(ONNXRUNTIME_LIBRARY onnxruntime)
if(ONNXRUNTIME_INCLUDE_DIR)
  target_include_directories(essential_audio PRIVATE "${ONNXRUNTIME_INCLUDE_DIR}")
endif()
if(ONNXRUNTIME_LIBRARY)
  target_link_libraries(essential_audio PRIVATE "${ONNXRUNTIME_LIBRARY}")
endif()

if(ANDROID)
  target_link_libraries(essential_audio PRIVATE android log)
endif()
