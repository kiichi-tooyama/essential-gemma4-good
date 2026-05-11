#include "essential_mediapipe_runtime.h"

int32_t essential_mediapipe_runtime_prepare_frame(
    int32_t width,
    int32_t height,
    int32_t channels) {
  if (width <= 0 || height <= 0 || channels <= 0) {
    return 1;
  }
  return 0;
}