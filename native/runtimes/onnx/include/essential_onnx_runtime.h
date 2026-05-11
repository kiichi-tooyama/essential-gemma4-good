#ifndef ESSENTIAL_ONNX_RUNTIME_H
#define ESSENTIAL_ONNX_RUNTIME_H

#include <stdint.h>

#if defined(_WIN32)
#define ESSENTIAL_ONNX_EXPORT __declspec(dllexport)
#else
#define ESSENTIAL_ONNX_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct essential_onnx_engine essential_onnx_engine;

ESSENTIAL_ONNX_EXPORT int32_t essential_onnx_runtime_is_available(void);

ESSENTIAL_ONNX_EXPORT essential_onnx_engine * essential_onnx_engine_create(
    const char * model_path);

ESSENTIAL_ONNX_EXPORT void essential_onnx_engine_destroy(
    essential_onnx_engine * engine);

ESSENTIAL_ONNX_EXPORT int32_t essential_onnx_engine_run(
    essential_onnx_engine * engine,
    const float * input_data,
    uint64_t input_length,
    const int64_t * input_shape,
    uint64_t input_shape_length,
    float ** output_data_out,
    uint64_t * output_length_out,
    int64_t ** output_shape_out,
    uint64_t * output_shape_length_out,
    char ** labels_csv_out);

ESSENTIAL_ONNX_EXPORT void essential_onnx_string_free(char * value);

ESSENTIAL_ONNX_EXPORT const char * essential_onnx_last_error_message(void);

#ifdef __cplusplus
}
#endif

#endif