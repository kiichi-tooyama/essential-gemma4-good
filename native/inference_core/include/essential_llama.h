#ifndef ESSENTIAL_LLAMA_H
#define ESSENTIAL_LLAMA_H

#include <stdint.h>

#if defined(_WIN32)
#define ESSENTIAL_LLAMA_EXPORT __declspec(dllexport)
#else
#define ESSENTIAL_LLAMA_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct essential_llama_engine essential_llama_engine;

typedef struct essential_llama_session_attachment_options {
  float scale;
} essential_llama_session_attachment_options;

typedef struct essential_llama_model_options {
  int32_t context_size;
  int32_t threads;
  int32_t batch_threads;
  int32_t gpu_layers;
  int32_t use_mmap;
  int32_t use_mlock;
} essential_llama_model_options;

typedef struct essential_llama_generation_options {
  int32_t max_tokens;
  int32_t top_k;
  float top_p;
  float temperature;
  uint32_t seed;
} essential_llama_generation_options;

typedef void (*essential_llama_token_callback)(
    const char * token,
    void * user_data);

ESSENTIAL_LLAMA_EXPORT essential_llama_engine * essential_llama_engine_create(
    const char * model_path,
    const essential_llama_model_options * options);

ESSENTIAL_LLAMA_EXPORT void essential_llama_engine_destroy(
    essential_llama_engine * engine);

ESSENTIAL_LLAMA_EXPORT int32_t essential_llama_engine_generate(
    essential_llama_engine * engine,
    const char * session_id,
    const char * prompt,
    const essential_llama_generation_options * options,
    essential_llama_token_callback callback,
    void * user_data,
    char ** output_out);

ESSENTIAL_LLAMA_EXPORT int32_t essential_llama_engine_attach_adapter(
    essential_llama_engine * engine,
    const char * session_id,
    const char * adapter_path,
    const essential_llama_session_attachment_options * options);

ESSENTIAL_LLAMA_EXPORT int32_t essential_llama_engine_detach_adapter(
    essential_llama_engine * engine,
    const char * session_id);

ESSENTIAL_LLAMA_EXPORT int32_t essential_llama_engine_cancel(
    essential_llama_engine * engine);

ESSENTIAL_LLAMA_EXPORT void essential_llama_string_free(char * value);

ESSENTIAL_LLAMA_EXPORT const char * essential_llama_last_error_message(void);

#ifdef __cplusplus
}
#endif

#endif