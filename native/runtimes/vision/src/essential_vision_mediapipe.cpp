// Essential Vision Runtime - MediaPipe Vision Implementation
// Wraps MediaPipe Vision Tasks for image analysis

#include "essential_vision_runtime.h"
#include <mediapipe/framework/calculator_graph.h>
#include <mediapipe/framework/formats/image.h>
#include <mediapipe/framework/formats/image_frame.h>
#include <mediapipe/framework/formats/detection.pb.h>
#include <mediapipe/framework/formats/landmark.pb.h>
#include <mediapipe/tasks/cc/vision/image_classifier/image_classifier.h>
#include <mediapipe/tasks/cc/vision/object_detector/object_detector.h>
#include <mediapipe/tasks/cc/vision/face_detector/face_detector.h>
#include <mediapipe/tasks/cc/vision/image_segmenter/image_segmenter.h>
#include <mediapipe/tasks/cc/vision/gesture_recognizer/gesture_recognizer.h>

#include <memory>
#include <string>
#include <vector>
#include <math>

using namespace mediapipe;
using namespace mediapipe::tasks::vision;

// Internal session state
struct EssentialVisionSession {
    EssentialVisionConfig config;
    
    // MediaPipe task runners
    std::unique_ptr<ImageClassifier> image_classifier;
    std::unique_ptr<ObjectDetector> object_detector;
    std::unique_ptr<FaceDetector> face_detector;
    std::unique_ptr<ImageSegmenter> image_segmenter;
    
    // Cancellation flag
    std::atomic<bool> cancelled{false};
    
    // Session ID for tracking
    std::string session_id;
};

struct EssentialVisionContext {
    // Global MediaPipe configuration
    std::string asset_base_path;
    bool gpu_enabled = false;
    
    // Error state
    std::string last_error;
};

// Helper: Convert EssentialImage to MediaPipe Image
static absl::StatusOr<Image> ConvertToMediaPipeImage(const EssentialImage* image) {
    ImageFormat::Format format;
    switch (image->format) {
        case ESSENTIAL_IMAGE_RGB:
            format = ImageFormat::SRGB;
            break;
        case ESSENTIAL_IMAGE_RGBA:
            format = ImageFormat::SRGBA;
            break;
        case ESSENTIAL_IMAGE_GRAYSCALE:
            format = ImageFormat::GRAY8;
            break;
        default:
            return absl::InvalidArgumentError("Unsupported image format");
    }
    
    // Create ImageFrame from raw data
    auto image_frame = std::make_shared<ImageFrame>(
        format,
        image->width,
        image->height,
        image->width * (format == ImageFormat::GRAY8 ? 1 : 
                         format == ImageFormat::SRGB ? 3 : 4),
        const_cast<uint8_t*>(image->data),
        [data = image->data](uint8_t*) {} // No-op deleter (we don't own the data)
    );
    
    return Image(image_frame);
}

// Helper: Apply EXIF orientation
static void ApplyOrientation(EssentialImage* image) {
    // Orientation values:
    // 1 = Normal, 2 = Flip horizontal, 3 = Rotate 180
    // 4 = Flip vertical, 5 = Transpose, 6 = Rotate 90
    // 7 = Transverse, 8 = Rotate 270
    
    // For now, just swap width/height for 90/270 degree rotations
    if (image->orientation >= 5 && image->orientation <= 8) {
        std::swap(image->width, image->height);
    }
}

// Context management
extern "C" {

EssentialVisionContextHandle essential_vision_create_context() {
    return new EssentialVisionContext();
}

void essential_vision_destroy_context(EssentialVisionContextHandle ctx) {
    delete ctx;
}

const char* essential_vision_get_last_error() {
    static thread_local std::string error_buffer;
    if (g_context && !g_context->last_error.empty()) {
        error_buffer = g_context->last_error;
        return error_buffer.c_str();
    }
    return nullptr;
}

// Session creation
EssentialVisionSessionHandle essential_vision_create_session(
    EssentialVisionContextHandle ctx,
    const EssentialVisionConfig* config
) {
    auto session = std::make_unique<EssentialVisionSession>();
    session->config = *config;
    session->session_id = "vision_" + std::to_string(reinterpret_cast<uintptr_t>(session.get()));
    
    try {
        switch (config->task_type) {
            case ESSENTIAL_VISION_CLASSIFICATION: {
                ImageClassifierOptions options;
                options.base_options.model_asset_path = config->model_path;
                options.classifier_options.max_results = config->top_k;
                options.classifier_options.score_threshold = config->confidence_threshold;
                options.running_mode = RunningMode::IMAGE;
                
                session->image_classifier = ImageClassifier::Create(
                    std::move(options)
                ).value();
                break;
            }
            
            case ESSENTIAL_VISION_DETECTION: {
                ObjectDetectorOptions options;
                options.base_options.model_asset_path = config->model_path;
                options.detector_options.score_threshold = config->confidence_threshold;
                options.running_mode = RunningMode::IMAGE;
                
                session->object_detector = ObjectDetector::Create(
                    std::move(options)
                ).value();
                break;
            }
            
            case ESSENTIAL_VISION_FACE_DETECTION: {
                FaceDetectorOptions options;
                options.base_options.model_asset_path = config->model_path;
                options.face_detector_options.min_detection_confidence = config->confidence_threshold;
                options.running_mode = RunningMode::IMAGE;
                
                session->face_detector = FaceDetector::Create(
                    std::move(options)
                ).value();
                break;
            }
            
            case ESSENTIAL_VISION_SEGMENTATION: {
                ImageSegmenterOptions options;
                options.base_options.model_asset_path = config->model_path;
                options.running_mode = RunningMode::IMAGE;
                options.output_category_mask = true;
                
                session->image_segmenter = ImageSegmenter::Create(
                    std::move(options)
                ).value();
                break;
            }
            
            default:
                // Tasks not using MediaPipe (OCR, Caption, Multimodal) 
                // will be handled by other runtimes
                break;
        }
        
        return session.release();
        
    } catch (const std::exception& e) {
        if (ctx) {
            ctx->last_error = std::string("Failed to create session: ") + e.what();
        }
        return nullptr;
    }
}

void essential_vision_destroy_session(EssentialVisionSessionHandle session) {
    delete session;
}

// Inference implementations
EssentialVisionResult* essential_vision_run_inference(
    EssentialVisionSessionHandle session,
    const EssentialImage* image
) {
    if (!session || !image) {
        return nullptr;
    }
    
    session->cancelled = false;
    auto start_time = std::chrono::high_resolution_clock::now();
    
    auto result = new EssentialVisionResult();
    std::memset(result, 0, sizeof(EssentialVisionResult));
    
    try {
        // Apply orientation correction
        EssentialImage oriented_image = *image;
        ApplyOrientation(&oriented_image);
        
        // Convert to MediaPipe Image
        auto mp_image = ConvertToMediaPipeImage(&oriented_image);
        if (!mp_image.ok()) {
            result->error_message = strdup(mp_image.status().ToString().c_str());
            return result;
        }
        
        switch (session->config.task_type) {
            case ESSENTIAL_VISION_CLASSIFICATION: {
                if (!session->image_classifier) {
                    result->error_message = strdup("Image classifier not initialized");
                    return result;
                }
                
                auto classification_result = session->image_classifier->Classify(
                    mp_image.value()
                );
                
                if (!classification_result.ok()) {
                    result->error_message = strdup(
                        classification_result.status().ToString().c_str()
                    );
                    return result;
                }
                
                // Convert results
                const auto& classifications = classification_result.value();
                result->num_classifications = classifications.classifications.size() > 0 
                    ? classifications.classifications[0].categories.size() 
                    : 0;
                result->classifications = new EssentialClassificationResult[result->num_classifications];
                
                if (classifications.classifications.size() > 0) {
                    size_t idx = 0;
                    for (const auto& category : classifications.classifications[0].categories) {
                        result->classifications[idx].label = strdup(category.category_name.c_str());
                        result->classifications[idx].label_id = strdup(category.category_name.c_str());
                        result->classifications[idx].confidence = category.score;
                        idx++;
                    }
                }
                break;
            }
            
            case ESSENTIAL_VISION_DETECTION: {
                if (!session->object_detector) {
                    result->error_message = strdup("Object detector not initialized");
                    return result;
                }
                
                auto detection_result = session->object_detector->Detect(
                    mp_image.value()
                );
                
                if (!detection_result.ok()) {
                    result->error_message = strdup(
                        detection_result.status().ToString().c_str()
                    );
                    return result;
                }
                
                // Convert detections
                const auto& detections = detection_result.value();
                result->num_detections = detections.detections.size();
                result->detections = new EssentialDetectionResult[result->num_detections];
                
                for (size_t i = 0; i < detections.detections.size(); i++) {
                    const auto& detection = detections.detections[i];
                    
                    // Get bounding box
                    const auto& bbox = detection.bounding_box;
                    result->detections[i].box.x = bbox.origin_x;
                    result->detections[i].box.y = bbox.origin_y;
                    result->detections[i].box.width = bbox.width;
                    result->detections[i].box.height = bbox.height;
                    result->detections[i].box.rotation = 0.0f;
                    
                    // Get label and confidence
                    if (detection.categories.size() > 0) {
                        result->detections[i].label = strdup(
                            detection.categories[0].category_name.c_str()
                        );
                        result->detections[i].confidence = detection.categories[0].score;
                    }
                }
                break;
            }
            
            case ESSENTIAL_VISION_FACE_DETECTION: {
                if (!session->face_detector) {
                    result->error_message = strdup("Face detector not initialized");
                    return result;
                }
                
                auto face_result = session->face_detector->Detect(
                    mp_image.value()
                );
                
                if (!face_result.ok()) {
                    result->error_message = strdup(
                        face_result.status().ToString().c_str()
                    );
                    return result;
                }
                
                // Convert face detections
                const auto& detections = face_result.value();
                result->num_detections = detections.detections.size();
                result->detections = new EssentialDetectionResult[result->num_detections];
                
                for (size_t i = 0; i < detections.detections.size(); i++) {
                    const auto& detection = detections.detections[i];
                    const auto& bbox = detection.bounding_box;
                    
                    result->detections[i].box.x = bbox.origin_x;
                    result->detections[i].box.y = bbox.origin_y;
                    result->detections[i].box.width = bbox.width;
                    result->detections[i].box.height = bbox.height;
                    result->detections[i].box.rotation = 0.0f;
                    result->detections[i].label = strdup("face");
                    
                    if (detection.categories.size() > 0) {
                        result->detections[i].confidence = detection.categories[0].score;
                    }
                }
                break;
            }
            
            default:
                result->error_message = strdup("Task type not supported by MediaPipe runtime");
                return result;
        }
        
        // Calculate latency
        auto end_time = std::chrono::high_resolution_clock::now();
        result->latency_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            end_time - start_time
        ).count();
        
    } catch (const std::exception& e) {
        result->error_message = strdup(e.what());
    }
    
    return result;
}

// Cleanup
void essential_vision_free_result(EssentialVisionResult* result) {
    if (!result) return;
    
    if (result->classifications) {
        for (size_t i = 0; i < result->num_classifications; i++) {
            free(result->classifications[i].label);
            free(result->classifications[i].label_id);
        }
        delete[] result->classifications;
    }
    
    if (result->detections) {
        for (size_t i = 0; i < result->num_detections; i++) {
            free(result->detections[i].label);
            free(result->detections[i].label_id);
        }
        delete[] result->detections;
    }
    
    if (result->text_regions) {
        for (size_t i = 0; i < result->num_text_regions; i++) {
            free(result->text_regions[i].text);
        }
        delete[] result->text_regions;
    }
    
    free(result->caption_text);
    free(result->error_message);
    
    delete result;
}

void essential_vision_cancel(EssentialVisionSessionHandle session) {
    if (session) {
        session->cancelled = true;
    }
}

} // extern "C"
