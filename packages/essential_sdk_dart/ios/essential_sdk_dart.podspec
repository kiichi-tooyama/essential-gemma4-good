Pod::Spec.new do |s|
  s.name             = 'essential_sdk_dart'
  s.version          = '0.1.0'
  s.summary          = 'Essential on-device inference SDK.'
  s.description      = 'Essential llama.cpp runtime bridge for Flutter.'
  s.homepage         = 'https://example.com/essential'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Essential' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = [
    'ios/Classes/**/*',
    '../../../native/inference_core/include/**/*.{h,hpp}',
    '../../../native/inference_core/src/**/*.{c,cc,cpp,h,hpp}',
    '../../../native/runtimes/llama/llama.cpp/include/**/*.{h,hpp}',
    '../../../native/runtimes/llama/llama.cpp/src/llama*.cpp',
    '../../../native/runtimes/llama/llama.cpp/src/unicode*.cpp',
    '../../../native/runtimes/llama/llama.cpp/src/models/gpt2.cpp',
    '../../../native/runtimes/llama/llama.cpp/src/models/llama.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/include/**/*.{h,hpp}',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml.c',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-alloc.c',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-backend.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-backend-dl.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-backend-meta.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-backend-reg.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-opt.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-quants.c',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-threading.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/gguf.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/ggml-cpu.c',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/ggml-cpu.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/binary-ops.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/unary-ops.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/ops.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/vec.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/traits.cpp',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/quants.c',
    '../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/arch/arm/quants.c',
    '../../../native/runtimes/vision/include/**/*.{h,hpp}',
    '../../../native/runtimes/vision/src/essential_vision_onnx.cpp',
    '../../../native/runtimes/audio/include/**/*.{h,hpp}',
    '../../../native/runtimes/audio/src/essential_audio_whisper.cpp',
    '../../../native/runtimes/audio/src/essential_audio_tts.cpp'
  ]
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'Accelerate', 'AVFoundation', 'CoreML'
  s.vendored_libraries = [
    '../../../native/third_party/onnxruntime/ios/libonnxruntime.a',
    '../../../native/third_party/whisper/ios/libwhisper.a'
  ]
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GGML_USE_CPU GGML_USE_ACCELERATE GGML_USE_METAL=0 GGML_USE_CUDA=0 GGML_USE_VULKAN=0 GGML_USE_SYCL=0 GGML_USE_OPENCL=0 ESSENTIAL_VISION_STANDALONE_ONNX=1 _DARWIN_C_SOURCE',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../../../native/inference_core/include" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/vision/include" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/audio/include" "${PODS_TARGET_SRCROOT}/../../../native/third_party/onnxruntime/include" "${PODS_TARGET_SRCROOT}/../../../native/third_party/whisper/include" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/include" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/src" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/src/models" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/ggml/include" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/ggml/src" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/../../../native/runtimes/llama/llama.cpp/ggml/src/ggml-cpu/arch/arm"'
  }
  s.swift_version = '5.0'
end
