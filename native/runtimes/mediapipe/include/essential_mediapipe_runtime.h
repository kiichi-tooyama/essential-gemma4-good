#ifndef ESSENTIAL_MEDIAPIPE_RUNTIME_H
#define ESSENTIAL_MEDIAPIPE_RUNTIME_H

#include <stdint.h>

#if defined(_WIN32)
#define ESSENTIAL_MEDIAPIPE_EXPORT __declspec(dllexport)
#else
#define ESSENTIAL_MEDIAPIPE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

ESSENTIAL_MEDIAPIPE_EXPORT int32_t essential_mediapipe_runtime_prepare_frame(
    int32_t width,
    int32_t height,
    int32_t channels);

#ifdef __cplusplus
}
#endif

#endif