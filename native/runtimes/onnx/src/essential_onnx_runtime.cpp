#include "essential_onnx_runtime.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

struct OrtEnv;
struct OrtSession;
struct OrtSessionOptions;
struct OrtMemoryInfo;
struct OrtValue;
struct OrtTensorTypeAndShapeInfo;
struct OrtStatus;

typedef enum OrtLoggingLevel {
  ORT_LOGGING_LEVEL_VERBOSE = 0,
  ORT_LOGGING_LEVEL_INFO = 1,
  ORT_LOGGING_LEVEL_WARNING = 2,
  ORT_LOGGING_LEVEL_ERROR = 3,
  ORT_LOGGING_LEVEL_FATAL = 4,
} OrtLoggingLevel;

typedef enum OrtAllocatorType {
  OrtInvalidAllocator = -1,
  OrtDeviceAllocator = 0,
  OrtArenaAllocator = 1,
} OrtAllocatorType;

typedef enum OrtMemType {
  OrtMemTypeCPUInput = -2,
  OrtMemTypeCPUOutput = -1,
  OrtMemTypeDefault = 0,
} OrtMemType;

typedef enum ONNXTensorElementDataType {
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED = 0,
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1,
} ONNXTensorElementDataType;

typedef struct OrtAllocator {
  uint32_t version;
  void * (*Alloc)(struct OrtAllocator * this_, size_t size);
  void (*Free)(struct OrtAllocator * this_, void * p);
  const struct OrtMemoryInfo * (*Info)(const struct OrtAllocator * this_);
} OrtAllocator;

typedef struct OrtApiBase {
  const void * (*GetApi)(uint32_t version);
  const char * (*GetVersionString)(void);
} OrtApiBase;

typedef const OrtApiBase * (*OrtGetApiBaseFn)(void);

typedef OrtStatus * (*OrtCreateEnvFn)(
    OrtLoggingLevel log_severity_level,
    const char * logid,
    OrtEnv ** out);
typedef OrtStatus * (*OrtCreateSessionFn)(
    const OrtEnv * env,
    const char * model_path,
    const OrtSessionOptions * options,
    OrtSession ** out);
typedef OrtStatus * (*OrtRunFn)(
    OrtSession * session,
    const void * run_options,
    const char * const * input_names,
    const OrtValue * const * inputs,
    size_t input_len,
    const char * const * output_names,
    size_t output_names_len,
    OrtValue ** outputs);
typedef OrtStatus * (*OrtCreateSessionOptionsFn)(OrtSessionOptions ** options);
typedef OrtStatus * (*OrtSessionGetCountFn)(const OrtSession * session, size_t * out);
typedef OrtStatus * (*OrtSessionGetNameFn)(
    const OrtSession * session,
    size_t index,
    OrtAllocator * allocator,
    char ** value);
typedef OrtStatus * (*OrtCreateTensorWithDataAsOrtValueFn)(
    const OrtMemoryInfo * info,
    void * p_data,
    size_t p_data_len,
    const int64_t * shape,
    size_t shape_len,
    ONNXTensorElementDataType type,
    OrtValue ** out);
typedef OrtStatus * (*OrtIsTensorFn)(const OrtValue * value, int * out);
typedef OrtStatus * (*OrtGetTensorMutableDataFn)(OrtValue * value, void ** out);
typedef OrtStatus * (*OrtGetDimensionsCountFn)(
    const OrtTensorTypeAndShapeInfo * info,
    size_t * out);
typedef OrtStatus * (*OrtGetDimensionsFn)(
    const OrtTensorTypeAndShapeInfo * info,
    int64_t * dim_values,
    size_t dim_values_length);
typedef OrtStatus * (*OrtGetTensorTypeAndShapeFn)(
    const OrtValue * value,
    OrtTensorTypeAndShapeInfo ** out);
typedef OrtStatus * (*OrtCreateCpuMemoryInfoFn)(
    OrtAllocatorType type,
    OrtMemType mem_type,
    OrtMemoryInfo ** out);
typedef void (*OrtReleaseEnvFn)(OrtEnv * input);
typedef void (*OrtReleaseStatusFn)(OrtStatus * input);
typedef void (*OrtReleaseMemoryInfoFn)(OrtMemoryInfo * input);
typedef void (*OrtReleaseSessionFn)(OrtSession * input);
typedef void (*OrtReleaseValueFn)(OrtValue * input);
typedef void (*OrtReleaseTensorTypeAndShapeInfoFn)(OrtTensorTypeAndShapeInfo * input);
typedef void (*OrtReleaseSessionOptionsFn)(OrtSessionOptions * input);
typedef OrtStatus * (*OrtCreateAllocatorFn)(
    const OrtSession * session,
    const OrtMemoryInfo * mem_info,
    OrtAllocator ** out);
typedef void (*OrtReleaseAllocatorFn)(OrtAllocator * input);
typedef const char * (*OrtGetErrorMessageFn)(const OrtStatus * status);

struct essential_onnx_engine {
  void * library_handle;
  const void * api;
  OrtEnv * env;
  OrtSession * session;
  OrtAllocator * allocator;
  OrtMemoryInfo * memory_info;
  std::string input_name;
  std::string output_name;
};

namespace {

constexpr uint32_t kOrtApiVersion = 24;
constexpr size_t kOrtIndexGetErrorMessage = 2;
constexpr size_t kOrtIndexCreateEnv = 3;
constexpr size_t kOrtIndexCreateSession = 7;
constexpr size_t kOrtIndexRun = 9;
constexpr size_t kOrtIndexCreateSessionOptions = 10;
constexpr size_t kOrtIndexSessionGetInputCount = 30;
constexpr size_t kOrtIndexSessionGetOutputCount = 31;
constexpr size_t kOrtIndexSessionGetInputName = 36;
constexpr size_t kOrtIndexSessionGetOutputName = 37;
constexpr size_t kOrtIndexCreateTensorWithDataAsOrtValue = 49;
constexpr size_t kOrtIndexIsTensor = 50;
constexpr size_t kOrtIndexGetTensorMutableData = 51;
constexpr size_t kOrtIndexGetDimensionsCount = 61;
constexpr size_t kOrtIndexGetDimensions = 62;
constexpr size_t kOrtIndexGetTensorTypeAndShape = 65;
constexpr size_t kOrtIndexCreateCpuMemoryInfo = 69;
constexpr size_t kOrtIndexReleaseEnv = 92;
constexpr size_t kOrtIndexReleaseStatus = 93;
constexpr size_t kOrtIndexReleaseMemoryInfo = 94;
constexpr size_t kOrtIndexReleaseSession = 95;
constexpr size_t kOrtIndexReleaseValue = 96;
constexpr size_t kOrtIndexReleaseTensorTypeAndShapeInfo = 99;
constexpr size_t kOrtIndexReleaseSessionOptions = 100;
constexpr size_t kOrtIndexCreateAllocator = 131;
constexpr size_t kOrtIndexReleaseAllocator = 132;

thread_local std::string g_last_error;

void set_last_error(const std::string & message) {
  g_last_error = message;
}

template <typename Fn>
Fn api_at(const void * api, size_t index) {
  return reinterpret_cast<Fn>(
      const_cast<void *>(reinterpret_cast<const void * const *>(api)[index]));
}

#if defined(_WIN32)
void * open_library(const char * name) {
  return reinterpret_cast<void *>(LoadLibraryA(name));
}

void * load_symbol(void * handle, const char * name) {
  return reinterpret_cast<void *>(GetProcAddress(
      static_cast<HMODULE>(handle),
      name));
}

void close_library(void * handle) {
  if (handle != nullptr) {
    FreeLibrary(static_cast<HMODULE>(handle));
  }
}
#else
void * open_library(const char * name) {
  return dlopen(name, RTLD_LAZY | RTLD_LOCAL);
}

void * load_symbol(void * handle, const char * name) {
  return dlsym(handle, name);
}

void close_library(void * handle) {
  if (handle != nullptr) {
    dlclose(handle);
  }
}
#endif

void * open_onnx_library() {
  static const std::array<const char *, 5> candidates = {
      "libonnxruntime.dylib",
      "libonnxruntime.so",
      "onnxruntime.dll",
      "@rpath/libonnxruntime.dylib",
      "/opt/homebrew/lib/libonnxruntime.dylib",
  };

  for (const char * candidate : candidates) {
    void * handle = open_library(candidate);
    if (handle != nullptr) {
      return handle;
    }
  }
  return nullptr;
}

bool copy_string(char ** out, const std::string & value) {
  if (out == nullptr) {
    return false;
  }
  char * buffer = static_cast<char *>(std::malloc(value.size() + 1));
  if (buffer == nullptr) {
    return false;
  }
  std::memcpy(buffer, value.c_str(), value.size() + 1);
  *out = buffer;
  return true;
}

bool copy_output_shape(
    const std::vector<int64_t> & shape,
    int64_t ** output_shape_out,
    uint64_t * output_shape_length_out) {
  if (output_shape_out == nullptr || output_shape_length_out == nullptr) {
    return false;
  }
  int64_t * values = static_cast<int64_t *>(
      std::malloc(sizeof(int64_t) * std::max<size_t>(1, shape.size())));
  if (values == nullptr) {
    return false;
  }
  if (!shape.empty()) {
    std::memcpy(values, shape.data(), sizeof(int64_t) * shape.size());
  }
  *output_shape_out = values;
  *output_shape_length_out = static_cast<uint64_t>(shape.size());
  return true;
}

bool copy_output_data(
    const float * data,
    size_t length,
    float ** output_data_out,
    uint64_t * output_length_out) {
  if (output_data_out == nullptr || output_length_out == nullptr) {
    return false;
  }
  float * values = static_cast<float *>(std::malloc(sizeof(float) * std::max<size_t>(1, length)));
  if (values == nullptr) {
    return false;
  }
  if (length > 0) {
    std::memcpy(values, data, sizeof(float) * length);
  }
  *output_data_out = values;
  *output_length_out = static_cast<uint64_t>(length);
  return true;
}

bool get_name(
    essential_onnx_engine * engine,
    size_t index_fn,
    const OrtSession * session,
    std::string * value_out) {
  auto get_name_fn = api_at<OrtSessionGetNameFn>(engine->api, index_fn);
  char * name = nullptr;
  OrtStatus * status = get_name_fn(session, 0, engine->allocator, &name);
  if (status != nullptr) {
    auto get_error_message = api_at<OrtGetErrorMessageFn>(
        engine->api,
        kOrtIndexGetErrorMessage);
    set_last_error(get_error_message(status));
    auto release_status = api_at<OrtReleaseStatusFn>(
        engine->api,
        kOrtIndexReleaseStatus);
    release_status(status);
    return false;
  }
  value_out->assign(name != nullptr ? name : "");
  if (name != nullptr) {
    engine->allocator->Free(engine->allocator, name);
  }
  return true;
}

bool consume_status(
    essential_onnx_engine * engine,
    OrtStatus * status,
    const char * fallback_message) {
  if (status == nullptr) {
    return true;
  }
  auto get_error_message = api_at<OrtGetErrorMessageFn>(
      engine->api,
      kOrtIndexGetErrorMessage);
  set_last_error(get_error_message != nullptr ? get_error_message(status) : fallback_message);
  auto release_status = api_at<OrtReleaseStatusFn>(
      engine->api,
      kOrtIndexReleaseStatus);
  release_status(status);
  return false;
}

}  // namespace

int32_t essential_onnx_runtime_is_available(void) {
  set_last_error(std::string());
  void * handle = open_onnx_library();
  if (handle == nullptr) {
    set_last_error("ONNX Runtime library is not available.");
    return 0;
  }
  close_library(handle);
  return 1;
}

essential_onnx_engine * essential_onnx_engine_create(const char * model_path) {
  set_last_error(std::string());
  if (model_path == nullptr || std::strlen(model_path) == 0) {
    set_last_error("ONNX model path is empty.");
    return nullptr;
  }

  void * library = open_onnx_library();
  if (library == nullptr) {
    set_last_error("Unable to load ONNX Runtime shared library.");
    return nullptr;
  }

  auto get_api_base = reinterpret_cast<OrtGetApiBaseFn>(
      load_symbol(library, "OrtGetApiBase"));
  if (get_api_base == nullptr) {
    close_library(library);
    set_last_error("OrtGetApiBase symbol was not found.");
    return nullptr;
  }

  const OrtApiBase * api_base = get_api_base();
  if (api_base == nullptr || api_base->GetApi == nullptr) {
    close_library(library);
    set_last_error("Failed to initialize OrtApiBase.");
    return nullptr;
  }

  const void * api = api_base->GetApi(kOrtApiVersion);
  if (api == nullptr) {
    close_library(library);
    set_last_error("Requested ONNX Runtime API version is unsupported.");
    return nullptr;
  }

  auto * engine = new essential_onnx_engine{
      library,
      api,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      std::string(),
      std::string(),
  };

  auto create_env = api_at<OrtCreateEnvFn>(api, kOrtIndexCreateEnv);
  if (!consume_status(engine, create_env(ORT_LOGGING_LEVEL_WARNING, "essential", &engine->env), "CreateEnv failed.")) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  auto create_session_options = api_at<OrtCreateSessionOptionsFn>(
      api,
      kOrtIndexCreateSessionOptions);
  OrtSessionOptions * session_options = nullptr;
  if (!consume_status(engine, create_session_options(&session_options), "CreateSessionOptions failed.")) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  auto create_session = api_at<OrtCreateSessionFn>(api, kOrtIndexCreateSession);
  if (!consume_status(
          engine,
          create_session(engine->env, model_path, session_options, &engine->session),
          "CreateSession failed.")) {
    auto release_session_options = api_at<OrtReleaseSessionOptionsFn>(
        api,
        kOrtIndexReleaseSessionOptions);
    release_session_options(session_options);
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  auto release_session_options = api_at<OrtReleaseSessionOptionsFn>(
      api,
      kOrtIndexReleaseSessionOptions);
  release_session_options(session_options);

  auto create_cpu_memory_info = api_at<OrtCreateCpuMemoryInfoFn>(
      api,
      kOrtIndexCreateCpuMemoryInfo);
  if (!consume_status(
          engine,
          create_cpu_memory_info(OrtArenaAllocator, OrtMemTypeDefault, &engine->memory_info),
          "CreateCpuMemoryInfo failed.")) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  auto create_allocator = api_at<OrtCreateAllocatorFn>(api, kOrtIndexCreateAllocator);
  if (!consume_status(
          engine,
          create_allocator(engine->session, engine->memory_info, &engine->allocator),
          "CreateAllocator failed.")) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  size_t input_count = 0;
  size_t output_count = 0;
  auto session_get_input_count = api_at<OrtSessionGetCountFn>(
      api,
      kOrtIndexSessionGetInputCount);
  auto session_get_output_count = api_at<OrtSessionGetCountFn>(
      api,
      kOrtIndexSessionGetOutputCount);
  if (!consume_status(engine, session_get_input_count(engine->session, &input_count), "SessionGetInputCount failed.") ||
      !consume_status(engine, session_get_output_count(engine->session, &output_count), "SessionGetOutputCount failed.")) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }
  if (input_count == 0 || output_count == 0) {
    essential_onnx_engine_destroy(engine);
    set_last_error("ONNX model has no inputs or outputs.");
    return nullptr;
  }

  if (!get_name(engine, kOrtIndexSessionGetInputName, engine->session, &engine->input_name) ||
      !get_name(engine, kOrtIndexSessionGetOutputName, engine->session, &engine->output_name)) {
    essential_onnx_engine_destroy(engine);
    return nullptr;
  }

  return engine;
}

void essential_onnx_engine_destroy(essential_onnx_engine * engine) {
  if (engine == nullptr) {
    return;
  }
  if (engine->api != nullptr) {
    if (engine->allocator != nullptr) {
      auto release_allocator = api_at<OrtReleaseAllocatorFn>(
          engine->api,
          kOrtIndexReleaseAllocator);
      release_allocator(engine->allocator);
    }
    if (engine->memory_info != nullptr) {
      auto release_memory_info = api_at<OrtReleaseMemoryInfoFn>(
          engine->api,
          kOrtIndexReleaseMemoryInfo);
      release_memory_info(engine->memory_info);
    }
    if (engine->session != nullptr) {
      auto release_session = api_at<OrtReleaseSessionFn>(
          engine->api,
          kOrtIndexReleaseSession);
      release_session(engine->session);
    }
    if (engine->env != nullptr) {
      auto release_env = api_at<OrtReleaseEnvFn>(engine->api, kOrtIndexReleaseEnv);
      release_env(engine->env);
    }
  }
  close_library(engine->library_handle);
  delete engine;
}

int32_t essential_onnx_engine_run(
    essential_onnx_engine * engine,
    const float * input_data,
    uint64_t input_length,
    const int64_t * input_shape,
    uint64_t input_shape_length,
    float ** output_data_out,
    uint64_t * output_length_out,
    int64_t ** output_shape_out,
    uint64_t * output_shape_length_out,
    char ** labels_csv_out) {
  set_last_error(std::string());
  if (engine == nullptr || engine->session == nullptr || engine->api == nullptr) {
    set_last_error("ONNX engine is not initialized.");
    return 1;
  }
  if (input_data == nullptr || input_shape == nullptr || input_shape_length == 0) {
    set_last_error("ONNX input tensor is invalid.");
    return 1;
  }
  if (output_data_out == nullptr || output_length_out == nullptr ||
      output_shape_out == nullptr || output_shape_length_out == nullptr ||
      labels_csv_out == nullptr) {
    set_last_error("ONNX output buffers are invalid.");
    return 1;
  }

  *output_data_out = nullptr;
  *output_length_out = 0;
  *output_shape_out = nullptr;
  *output_shape_length_out = 0;
  *labels_csv_out = nullptr;

  auto create_tensor = api_at<OrtCreateTensorWithDataAsOrtValueFn>(
      engine->api,
      kOrtIndexCreateTensorWithDataAsOrtValue);
  OrtValue * input_tensor = nullptr;
  if (!consume_status(
          engine,
          create_tensor(
              engine->memory_info,
              const_cast<float *>(input_data),
              static_cast<size_t>(input_length * sizeof(float)),
              input_shape,
              static_cast<size_t>(input_shape_length),
              ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
              &input_tensor),
          "CreateTensorWithDataAsOrtValue failed.")) {
    return 1;
  }

  auto is_tensor = api_at<OrtIsTensorFn>(engine->api, kOrtIndexIsTensor);
  int tensor_flag = 0;
  if (!consume_status(engine, is_tensor(input_tensor, &tensor_flag), "IsTensor failed.") ||
      tensor_flag == 0) {
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_value(input_tensor);
    set_last_error("Created ONNX input is not a tensor.");
    return 1;
  }

  const char * input_names[] = {engine->input_name.c_str()};
  const OrtValue * inputs[] = {input_tensor};
  const char * output_names[] = {engine->output_name.c_str()};
  OrtValue * outputs[] = {nullptr};
  auto run = api_at<OrtRunFn>(engine->api, kOrtIndexRun);
  if (!consume_status(
          engine,
          run(engine->session, nullptr, input_names, inputs, 1, output_names, 1, outputs),
          "Run failed.")) {
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_value(input_tensor);
    return 1;
  }

  OrtTensorTypeAndShapeInfo * shape_info = nullptr;
  auto get_shape = api_at<OrtGetTensorTypeAndShapeFn>(
      engine->api,
      kOrtIndexGetTensorTypeAndShape);
  if (!consume_status(
          engine,
          get_shape(outputs[0], &shape_info),
          "GetTensorTypeAndShape failed.")) {
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_value(outputs[0]);
    release_value(input_tensor);
    return 1;
  }

  size_t dimension_count = 0;
  auto get_dimensions_count = api_at<OrtGetDimensionsCountFn>(
      engine->api,
      kOrtIndexGetDimensionsCount);
  if (!consume_status(
          engine,
          get_dimensions_count(shape_info, &dimension_count),
          "GetDimensionsCount failed.")) {
    auto release_shape = api_at<OrtReleaseTensorTypeAndShapeInfoFn>(
        engine->api,
        kOrtIndexReleaseTensorTypeAndShapeInfo);
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_shape(shape_info);
    release_value(outputs[0]);
    release_value(input_tensor);
    return 1;
  }

  std::vector<int64_t> shape(dimension_count);
  auto get_dimensions = api_at<OrtGetDimensionsFn>(engine->api, kOrtIndexGetDimensions);
  if (dimension_count > 0 &&
      !consume_status(
          engine,
          get_dimensions(shape_info, shape.data(), dimension_count),
          "GetDimensions failed.")) {
    auto release_shape = api_at<OrtReleaseTensorTypeAndShapeInfoFn>(
        engine->api,
        kOrtIndexReleaseTensorTypeAndShapeInfo);
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_shape(shape_info);
    release_value(outputs[0]);
    release_value(input_tensor);
    return 1;
  }

  size_t element_count = 1;
  for (int64_t dimension : shape) {
    element_count *= static_cast<size_t>(std::max<int64_t>(1, dimension));
  }

  void * raw_output = nullptr;
  auto get_tensor_data = api_at<OrtGetTensorMutableDataFn>(
      engine->api,
      kOrtIndexGetTensorMutableData);
  if (!consume_status(
          engine,
          get_tensor_data(outputs[0], &raw_output),
          "GetTensorMutableData failed.")) {
    auto release_shape = api_at<OrtReleaseTensorTypeAndShapeInfoFn>(
        engine->api,
        kOrtIndexReleaseTensorTypeAndShapeInfo);
    auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
    release_shape(shape_info);
    release_value(outputs[0]);
    release_value(input_tensor);
    return 1;
  }

  const float * typed_output = static_cast<const float *>(raw_output);
  bool copied_output = copy_output_data(
      typed_output,
      element_count,
      output_data_out,
      output_length_out);
  bool copied_shape = copy_output_shape(
      shape,
      output_shape_out,
      output_shape_length_out);
  bool copied_labels = copy_string(labels_csv_out, std::string());

  auto release_shape = api_at<OrtReleaseTensorTypeAndShapeInfoFn>(
      engine->api,
      kOrtIndexReleaseTensorTypeAndShapeInfo);
  auto release_value = api_at<OrtReleaseValueFn>(engine->api, kOrtIndexReleaseValue);
  release_shape(shape_info);
  release_value(outputs[0]);
  release_value(input_tensor);

  if (!copied_output || !copied_shape || !copied_labels) {
    std::free(*output_data_out);
    std::free(*output_shape_out);
    std::free(*labels_csv_out);
    *output_data_out = nullptr;
    *output_shape_out = nullptr;
    *labels_csv_out = nullptr;
    *output_length_out = 0;
    *output_shape_length_out = 0;
    set_last_error("Failed to allocate ONNX output buffers.");
    return 1;
  }

  return 0;
}

void essential_onnx_string_free(char * value) {
  std::free(value);
}

const char * essential_onnx_last_error_message(void) {
  return g_last_error.c_str();
}