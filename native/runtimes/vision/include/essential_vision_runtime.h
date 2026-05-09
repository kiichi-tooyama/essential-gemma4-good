// Essential Vision Runtime - C API Header
// Provides unified interface for MediaPipe Vision and ONNX Runtime

#ifndef ESSENTIAL_VISION_RUNTIME_H
#define ESSENTIAL_VISION_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles
typedef struct EssentialVisionContext* EssentialVisionContextHandle;
typedef struct EssentialVisionSession* EssentialVisionSessionHandle;

// Task types
typedef enum {
    ESSENTIAL_VISION_CLASSIFICATION = 0,
    ESSENTIAL_VISION_DETECTION = 1,
    ESSENTIAL_VISION_SEGMENTATION = 2,
    ESSENTIAL_VISION_OCR = 3,
    ESSENTIAL_VISION_CAPTION = 4,
    ESSENTIAL_VISION_FACE_DETECTION = 5,
    ESSENTIAL_VISION_MULTIMODAL_CHAT = 6,
} EssentialVisionTaskType;

// Image format
typedef enum {
    ESSENTIAL_IMAGE_RGB = 0,
    ESSENTIAL_IMAGE_RGBA = 1,
    ESSENTIAL_IMAGE_BGR = 2,
    ESSENTIAL_IMAGE_GRAYSCALE = 3,
    ESSENTIAL_IMAGE_YUV420 = 4,
} EssentialImageFormat;

// Image data structure
typedef struct {
    uint8_t* data;
    size_t data_size;
    int width;
    int height;
    EssentialImageFormat format;
    int orientation; // EXIF orientation (1-8)
} EssentialImage;

// Classification result
typedef struct {
    char* label;
    char* label_id;
    float confidence;
} EssentialClassificationResult;

// Detection box (normalized 0-1)
typedef struct {
    float x, y, width, height;
    float rotation;
} EssentialDetectionBox;

// Detection result
typedef struct {
    char* label;
    char* label_id;
    float confidence;
    EssentialDetectionBox box;
} EssentialDetectionResult;

// OCR text region
typedef struct {
    char* text;
    float confidence;
    EssentialDetectionBox box;
} EssentialTextRegion;

// Vision result
typedef struct {
    EssentialClassificationResult* classifications;
    size_t num_classifications;
    
    EssentialDetectionResult* detections;
    size_t num_detections;
    
    EssentialTextRegion* text_regions;
    size_t num_text_regions;
    
    char* caption_text;
    
    int latency_ms;
    char** model_bundle_used;
    size_t num_models;
    
    char* error_message;
} EssentialVisionResult;

// Session configuration
typedef struct {
    EssentialVisionTaskType task_type;
    const char* model_path;
    const char* label_map_path;
    int target_width;
    int target_height;
    float confidence_threshold;
    int top_k;
    bool use_gpu;
} EssentialVisionConfig;

// Context management
EssentialVisionContextHandle essential_vision_create_context();
void essential_vision_destroy_context(EssentialVisionContextHandle ctx);

// Session management
EssentialVisionSessionHandle essential_vision_create_session(
    EssentialVisionContextHandle ctx,
    const EssentialVisionConfig* config
);
void essential_vision_destroy_session(EssentialVisionSessionHandle session);

// Synchronous inference
EssentialVisionResult* essential_vision_run_inference(
    EssentialVisionSessionHandle session,
    const EssentialImage* image
);

// Streaming inference (for multimodal chat)
typedef void (*EssentialVisionTokenCallback)(
    const char* token,
    bool is_final,
    void* user_data
);

int essential_vision_run_streaming(
    EssentialVisionSessionHandle session,
    const EssentialImage* image,
    const char* text_prompt,
    EssentialVisionTokenCallback callback,
    void* user_data
);

// Cancel ongoing inference
void essential_vision_cancel(EssentialVisionSessionHandle session);

// Result cleanup
void essential_vision_free_result(EssentialVisionResult* result);

// Error handling
const char* essential_vision_get_last_error();

// Preprocessing helpers
int essential_vision_preprocess_image(
    const EssentialImage* input,
    EssentialImage* output,
    int target_width,
    int target_height,
    bool normalize,
    bool letterbox
);

void essential_vision_free_image(EssentialImage* image);

// MediaPipe specific initialization
int essential_vision_init_mediapipe(
    EssentialVisionContextHandle ctx,
    const char* model_asset_path
);

// ONNX Runtime specific initialization
int essential_vision_init_onnx(
    EssentialVisionContextHandle ctx,
    const char* model_path,
    bool use_gpu
);

#ifdef __cplusplus
}
#endif

#endif // ESSENTIAL_VISION_RUNTIME_H
