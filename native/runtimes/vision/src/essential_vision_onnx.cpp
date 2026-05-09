// Essential Vision Runtime - ONNX Runtime Vision Implementation
// Provides image classification and object detection through the ONNX Runtime C API.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <numeric>
#include <string>
#include <utility>
#include <vector>

#include "essential_vision_runtime.h"
#include <onnxruntime_c_api.h>

#if defined(__APPLE__)
extern "C" OrtStatus* OrtSessionOptionsAppendExecutionProvider_CoreML(
    OrtSessionOptions* options,
    uint32_t coreml_flags) __attribute__((weak));
#endif

#if !defined(_WIN32)
extern "C" OrtStatus* OrtSessionOptionsAppendExecutionProvider_CUDA(
    OrtSessionOptions* options,
    int device_id) __attribute__((weak));
#endif

namespace {

constexpr int kDefaultInputWidth = 224;
constexpr int kDefaultInputHeight = 224;
constexpr int kDefaultChannels = 3;
constexpr int kDefaultTopK = 5;
constexpr float kDefaultConfidenceThreshold = 0.25f;
constexpr float kLetterboxValue = 114.0f;

thread_local std::string g_last_error;

const OrtApi* ort_api() {
    return OrtGetApiBase()->GetApi(ORT_API_VERSION);
}

char* duplicate_string(const std::string& value) {
    char* output = static_cast<char*>(std::malloc(value.size() + 1));
    if (!output) {
        return nullptr;
    }
    std::memcpy(output, value.c_str(), value.size() + 1);
    return output;
}

void set_last_error(const std::string& message) {
    g_last_error = message;
}

std::string consume_status(OrtStatus* status) {
    if (!status) {
        return {};
    }
    const OrtApi* api = ort_api();
    std::string message = api->GetErrorMessage(status);
    api->ReleaseStatus(status);
    set_last_error(message);
    return message;
}

bool check_status(OrtStatus* status, std::string* error) {
    if (!status) {
        return true;
    }
    if (error) {
        *error = consume_status(status);
    } else {
        consume_status(status);
    }
    return false;
}

EssentialVisionResult* make_empty_result() {
    auto* result = new EssentialVisionResult();
    std::memset(result, 0, sizeof(EssentialVisionResult));
    return result;
}

EssentialVisionResult* make_error_result(const std::string& message) {
    EssentialVisionResult* result = make_empty_result();
    result->error_message = duplicate_string(message);
    set_last_error(message);
    return result;
}

int channels_for_format(EssentialImageFormat format) {
    switch (format) {
        case ESSENTIAL_IMAGE_RGB:
        case ESSENTIAL_IMAGE_BGR:
            return 3;
        case ESSENTIAL_IMAGE_RGBA:
            return 4;
        case ESSENTIAL_IMAGE_GRAYSCALE:
            return 1;
        default:
            return 0;
    }
}

bool validate_image(const EssentialImage* image, std::string* error) {
    if (!image) {
        *error = "Image is null";
        return false;
    }
    if (!image->data || image->width <= 0 || image->height <= 0) {
        *error = "Image data, width, and height must be valid";
        return false;
    }
    const int channels = channels_for_format(image->format);
    if (channels == 0) {
        *error = "Unsupported image format for ONNX vision inference";
        return false;
    }
    const size_t required = static_cast<size_t>(image->width) *
                            static_cast<size_t>(image->height) *
                            static_cast<size_t>(channels);
    if (image->data_size < required) {
        *error = "Image data_size is smaller than the expected pixel buffer";
        return false;
    }
    return true;
}

std::vector<float> rgba_to_rgb(const EssentialImage* image) {
    const size_t pixel_count = static_cast<size_t>(image->width) *
                               static_cast<size_t>(image->height);
    std::vector<float> rgb(pixel_count * 3);

    for (size_t i = 0; i < pixel_count; ++i) {
        const uint8_t* src = image->data + i * 4;
        rgb[i * 3 + 0] = static_cast<float>(src[0]);
        rgb[i * 3 + 1] = static_cast<float>(src[1]);
        rgb[i * 3 + 2] = static_cast<float>(src[2]);
    }
    return rgb;
}

std::vector<float> image_to_rgb(const EssentialImage* image) {
    if (image->format == ESSENTIAL_IMAGE_RGBA) {
        return rgba_to_rgb(image);
    }

    const size_t pixel_count = static_cast<size_t>(image->width) *
                               static_cast<size_t>(image->height);
    std::vector<float> rgb(pixel_count * 3);

    for (size_t i = 0; i < pixel_count; ++i) {
        switch (image->format) {
            case ESSENTIAL_IMAGE_RGB:
                rgb[i * 3 + 0] = static_cast<float>(image->data[i * 3 + 0]);
                rgb[i * 3 + 1] = static_cast<float>(image->data[i * 3 + 1]);
                rgb[i * 3 + 2] = static_cast<float>(image->data[i * 3 + 2]);
                break;
            case ESSENTIAL_IMAGE_BGR:
                rgb[i * 3 + 0] = static_cast<float>(image->data[i * 3 + 2]);
                rgb[i * 3 + 1] = static_cast<float>(image->data[i * 3 + 1]);
                rgb[i * 3 + 2] = static_cast<float>(image->data[i * 3 + 0]);
                break;
            case ESSENTIAL_IMAGE_GRAYSCALE: {
                const float value = static_cast<float>(image->data[i]);
                rgb[i * 3 + 0] = value;
                rgb[i * 3 + 1] = value;
                rgb[i * 3 + 2] = value;
                break;
            }
            default:
                break;
        }
    }
    return rgb;
}

struct LetterboxInfo {
    float scale = 1.0f;
    int pad_x = 0;
    int pad_y = 0;
    int resized_width = 0;
    int resized_height = 0;
};

std::vector<float> preprocess_image_resize(
    const EssentialImage* image,
    int target_width,
    int target_height,
    LetterboxInfo* info) {
    const std::vector<float> src = image_to_rgb(image);
    std::vector<float> dst(
        static_cast<size_t>(target_width) * static_cast<size_t>(target_height) * 3,
        kLetterboxValue);

    const float scale = std::min(
        static_cast<float>(target_width) / static_cast<float>(image->width),
        static_cast<float>(target_height) / static_cast<float>(image->height));
    const int resized_width = std::max(1, static_cast<int>(std::round(image->width * scale)));
    const int resized_height = std::max(1, static_cast<int>(std::round(image->height * scale)));
    const int pad_x = (target_width - resized_width) / 2;
    const int pad_y = (target_height - resized_height) / 2;

    if (info) {
        info->scale = scale;
        info->pad_x = pad_x;
        info->pad_y = pad_y;
        info->resized_width = resized_width;
        info->resized_height = resized_height;
    }

    // Bilinear resize into the centered letterbox region.
    for (int y = 0; y < resized_height; ++y) {
        const float src_y = (static_cast<float>(y) + 0.5f) / scale - 0.5f;
        const int y0 = std::max(0, static_cast<int>(std::floor(src_y)));
        const int y1 = std::min(image->height - 1, y0 + 1);
        const float wy = src_y - static_cast<float>(y0);

        for (int x = 0; x < resized_width; ++x) {
            const float src_x = (static_cast<float>(x) + 0.5f) / scale - 0.5f;
            const int x0 = std::max(0, static_cast<int>(std::floor(src_x)));
            const int x1 = std::min(image->width - 1, x0 + 1);
            const float wx = src_x - static_cast<float>(x0);

            for (int c = 0; c < 3; ++c) {
                const float p00 = src[(static_cast<size_t>(y0) * image->width + x0) * 3 + c];
                const float p01 = src[(static_cast<size_t>(y0) * image->width + x1) * 3 + c];
                const float p10 = src[(static_cast<size_t>(y1) * image->width + x0) * 3 + c];
                const float p11 = src[(static_cast<size_t>(y1) * image->width + x1) * 3 + c];
                const float top = p00 + (p01 - p00) * wx;
                const float bottom = p10 + (p11 - p10) * wx;
                dst[(static_cast<size_t>(y + pad_y) * target_width + (x + pad_x)) * 3 + c] =
                    top + (bottom - top) * wy;
            }
        }
    }

    return dst;
}

void preprocess_image_normalize(std::vector<float>* image, bool minus_one_to_one) {
    for (float& value : *image) {
        value = minus_one_to_one ? (value / 127.5f - 1.0f) : (value / 255.0f);
    }
}

std::vector<float> hwc_to_chw(
    const std::vector<float>& hwc,
    int width,
    int height,
    int channels) {
    std::vector<float> chw(hwc.size());
    const size_t plane_size = static_cast<size_t>(width) * static_cast<size_t>(height);

    for (int c = 0; c < channels; ++c) {
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                chw[static_cast<size_t>(c) * plane_size + static_cast<size_t>(y) * width + x] =
                    hwc[(static_cast<size_t>(y) * width + x) * channels + c];
            }
        }
    }
    return chw;
}

std::vector<float> adapt_hwc_channels(
    const std::vector<float>& rgb,
    int width,
    int height,
    int channels) {
    if (channels == 3) {
        return rgb;
    }

    const size_t pixel_count = static_cast<size_t>(width) * static_cast<size_t>(height);
    std::vector<float> output(pixel_count * static_cast<size_t>(channels));
    for (size_t i = 0; i < pixel_count; ++i) {
        const float r = rgb[i * 3 + 0];
        const float g = rgb[i * 3 + 1];
        const float b = rgb[i * 3 + 2];
        if (channels == 1) {
            output[i] = 0.299f * r + 0.587f * g + 0.114f * b;
        } else if (channels == 4) {
            output[i * 4 + 0] = r;
            output[i * 4 + 1] = g;
            output[i * 4 + 2] = b;
            output[i * 4 + 3] = 1.0f;
        }
    }
    return output;
}

struct OrtValueHolder {
    OrtValue* value = nullptr;
    OrtValueHolder() = default;
    explicit OrtValueHolder(OrtValue* v) : value(v) {}
    OrtValueHolder(const OrtValueHolder&) = delete;
    OrtValueHolder& operator=(const OrtValueHolder&) = delete;
    OrtValueHolder(OrtValueHolder&& other) noexcept : value(other.value) {
        other.value = nullptr;
    }
    OrtValueHolder& operator=(OrtValueHolder&& other) noexcept {
        if (this != &other) {
            if (value) {
                ort_api()->ReleaseValue(value);
            }
            value = other.value;
            other.value = nullptr;
        }
        return *this;
    }
    ~OrtValueHolder() {
        if (value) {
            ort_api()->ReleaseValue(value);
        }
    }
};

struct OrtShapeInfoHolder {
    OrtTensorTypeAndShapeInfo* info = nullptr;
    ~OrtShapeInfoHolder() {
        if (info) {
            ort_api()->ReleaseTensorTypeAndShapeInfo(info);
        }
    }
};

std::string get_io_name(OrtSession* session, size_t index, bool input, OrtAllocator* allocator) {
    char* raw_name = nullptr;
    OrtStatus* status = input
        ? ort_api()->SessionGetInputName(session, index, allocator, &raw_name)
        : ort_api()->SessionGetOutputName(session, index, allocator, &raw_name);
    if (status) {
        consume_status(status);
        return {};
    }

    std::string name = raw_name ? raw_name : "";
    if (raw_name) {
        allocator->Free(allocator, raw_name);
    }
    return name;
}

std::vector<int64_t> get_input_shape(OrtSession* session, size_t index) {
    OrtTypeInfo* type_info = nullptr;
    if (!check_status(ort_api()->SessionGetInputTypeInfo(session, index, &type_info), nullptr)) {
        return {};
    }

    const OrtTensorTypeAndShapeInfo* tensor_info = ort_api()->CastTypeInfoToTensorInfo(type_info);
    std::vector<int64_t> dims;
    if (tensor_info) {
        size_t dim_count = 0;
        if (check_status(ort_api()->GetDimensionsCount(tensor_info, &dim_count), nullptr)) {
            dims.resize(dim_count);
            check_status(ort_api()->GetDimensions(tensor_info, dims.data(), dim_count), nullptr);
        }
    }
    ort_api()->ReleaseTypeInfo(type_info);
    return dims;
}

size_t shape_element_count(const std::vector<int64_t>& shape) {
    size_t count = 1;
    for (int64_t dim : shape) {
        if (dim <= 0) {
            continue;
        }
        count *= static_cast<size_t>(dim);
    }
    return count;
}

std::vector<int64_t> get_value_shape(OrtValue* value, std::string* error) {
    OrtShapeInfoHolder shape_holder;
    if (!check_status(ort_api()->GetTensorTypeAndShape(value, &shape_holder.info), error)) {
        return {};
    }
    size_t dim_count = 0;
    if (!check_status(ort_api()->GetDimensionsCount(shape_holder.info, &dim_count), error)) {
        return {};
    }
    std::vector<int64_t> shape(dim_count);
    check_status(ort_api()->GetDimensions(shape_holder.info, shape.data(), dim_count), error);
    return shape;
}

std::vector<float> softmax_if_needed(const float* data, size_t length) {
    std::vector<float> values(data, data + length);
    if (values.empty()) {
        return values;
    }

    const auto [min_it, max_it] = std::minmax_element(values.begin(), values.end());
    const float sum = std::accumulate(values.begin(), values.end(), 0.0f);
    if (*min_it >= 0.0f && *max_it <= 1.0f && sum > 0.9f && sum < 1.1f) {
        return values;
    }

    const float max_value = *max_it;
    float exp_sum = 0.0f;
    for (float& value : values) {
        value = std::exp(value - max_value);
        exp_sum += value;
    }
    if (exp_sum > 0.0f) {
        for (float& value : values) {
            value /= exp_sum;
        }
    }
    return values;
}

std::string class_label(int class_id) {
    return "class_" + std::to_string(class_id);
}

void parse_classification(
    const float* data,
    size_t length,
    int top_k,
    EssentialVisionResult* result) {
    std::vector<float> scores = softmax_if_needed(data, length);
    std::vector<size_t> indices(scores.size());
    std::iota(indices.begin(), indices.end(), 0);
    std::partial_sort(
        indices.begin(),
        indices.begin() + std::min<size_t>(top_k, indices.size()),
        indices.end(),
        [&scores](size_t a, size_t b) { return scores[a] > scores[b]; });

    result->num_classifications = std::min<size_t>(top_k, indices.size());
    result->classifications = new EssentialClassificationResult[result->num_classifications]();
    for (size_t i = 0; i < result->num_classifications; ++i) {
        const int class_id = static_cast<int>(indices[i]);
        const std::string label = class_label(class_id);
        result->classifications[i].label = duplicate_string(label);
        result->classifications[i].label_id = duplicate_string(std::to_string(class_id));
        result->classifications[i].confidence = scores[indices[i]];
    }
}

float sigmoid(float value) {
    return 1.0f / (1.0f + std::exp(-value));
}

float clamp01(float value) {
    return std::max(0.0f, std::min(1.0f, value));
}

struct DetectionCandidate {
    float x1 = 0.0f;
    float y1 = 0.0f;
    float x2 = 0.0f;
    float y2 = 0.0f;
    float score = 0.0f;
    int class_id = 0;
};

void add_detection_result(
    const std::vector<DetectionCandidate>& candidates,
    EssentialVisionResult* result) {
    result->num_detections = candidates.size();
    result->detections = new EssentialDetectionResult[result->num_detections]();

    for (size_t i = 0; i < candidates.size(); ++i) {
        const DetectionCandidate& candidate = candidates[i];
        const std::string label = class_label(candidate.class_id);
        result->detections[i].label = duplicate_string(label);
        result->detections[i].label_id = duplicate_string(std::to_string(candidate.class_id));
        result->detections[i].confidence = candidate.score;
        result->detections[i].box.x = clamp01(candidate.x1);
        result->detections[i].box.y = clamp01(candidate.y1);
        result->detections[i].box.width = clamp01(candidate.x2 - candidate.x1);
        result->detections[i].box.height = clamp01(candidate.y2 - candidate.y1);
        result->detections[i].box.rotation = 0.0f;
    }
}

void parse_detection_triplet(
    const float* boxes,
    const std::vector<int64_t>& box_shape,
    const float* scores,
    const std::vector<int64_t>& score_shape,
    const float* classes,
    const std::vector<int64_t>& class_shape,
    float threshold,
    int model_width,
    int model_height,
    int image_width,
    int image_height,
    const LetterboxInfo& letterbox,
    EssentialVisionResult* result) {
    if (box_shape.empty() || box_shape.back() != 4) {
        result->error_message = duplicate_string("Boxes output must have a final dimension of 4");
        return;
    }

    const size_t box_count = shape_element_count(box_shape) / 4;
    const size_t score_count = shape_element_count(score_shape);
    const size_t class_count = classes ? shape_element_count(class_shape) : score_count;
    const size_t count = std::min({box_count, score_count, class_count});
    std::vector<DetectionCandidate> candidates;

    for (size_t i = 0; i < count; ++i) {
        const float score = scores[i];
        if (score < threshold) {
            continue;
        }

        float y1 = boxes[i * 4 + 0];
        float x1 = boxes[i * 4 + 1];
        float y2 = boxes[i * 4 + 2];
        float x2 = boxes[i * 4 + 3];

        const bool normalized = std::max({std::fabs(x1), std::fabs(y1), std::fabs(x2), std::fabs(y2)}) <= 2.0f;
        if (normalized) {
            x1 *= static_cast<float>(model_width);
            x2 *= static_cast<float>(model_width);
            y1 *= static_cast<float>(model_height);
            y2 *= static_cast<float>(model_height);
        }

        DetectionCandidate candidate;
        candidate.score = score;
        candidate.class_id = classes ? static_cast<int>(std::round(classes[i])) : 0;

        const float inv_scale = letterbox.scale > 0.0f ? 1.0f / letterbox.scale : 1.0f;
        candidate.x1 = ((x1 - static_cast<float>(letterbox.pad_x)) * inv_scale) / static_cast<float>(image_width);
        candidate.y1 = ((y1 - static_cast<float>(letterbox.pad_y)) * inv_scale) / static_cast<float>(image_height);
        candidate.x2 = ((x2 - static_cast<float>(letterbox.pad_x)) * inv_scale) / static_cast<float>(image_width);
        candidate.y2 = ((y2 - static_cast<float>(letterbox.pad_y)) * inv_scale) / static_cast<float>(image_height);
        candidates.push_back(candidate);
    }

    std::sort(candidates.begin(), candidates.end(), [](const DetectionCandidate& a, const DetectionCandidate& b) {
        return a.score > b.score;
    });
    if (candidates.size() > 100) {
        candidates.resize(100);
    }
    add_detection_result(candidates, result);
}

void parse_detections(
    const float* data,
    const std::vector<int64_t>& shape,
    float threshold,
    int model_width,
    int model_height,
    int image_width,
    int image_height,
    const LetterboxInfo& letterbox,
    EssentialVisionResult* result) {
    if (shape.size() < 2) {
        result->error_message = duplicate_string("Detection output shape is unsupported");
        return;
    }

    int64_t rows = 0;
    int64_t attributes = 0;
    bool transposed_yolo = false;

    // Common layouts:
    //   [1, N, 6+]       -> x1,y1,x2,y2,score,class or class scores
    //   [1, 6+, N]       -> YOLO style transposed attributes
    //   [N, 6+]          -> batched dimension omitted
    if (shape.size() == 3 && shape[1] > 0 && shape[2] > 0) {
        if (shape[1] <= 128 && shape[2] > shape[1]) {
            transposed_yolo = true;
            attributes = shape[1];
            rows = shape[2];
        } else {
            rows = shape[1];
            attributes = shape[2];
        }
    } else {
        rows = shape[0];
        attributes = shape[1];
    }

    if (rows <= 0 || attributes < 6) {
        result->error_message = duplicate_string("Detection output must contain at least 6 attributes");
        return;
    }

    std::vector<DetectionCandidate> candidates;
    const int64_t max_rows = std::min<int64_t>(rows, 10000);

    for (int64_t row = 0; row < max_rows; ++row) {
        auto at = [&](int64_t attribute) -> float {
            if (transposed_yolo) {
                return data[static_cast<size_t>(attribute) * static_cast<size_t>(rows) + row];
            }
            return data[static_cast<size_t>(row) * static_cast<size_t>(attributes) + attribute];
        };

        float x = at(0);
        float y = at(1);
        float w_or_x2 = at(2);
        float h_or_y2 = at(3);
        float objectness = at(4);
        float best_score = objectness;
        int class_id = 0;

        if (attributes == 6) {
            class_id = static_cast<int>(std::round(at(5)));
        } else {
            best_score = -std::numeric_limits<float>::infinity();
            for (int64_t attribute = 5; attribute < attributes; ++attribute) {
                float class_score = at(attribute);
                if (class_score < 0.0f || class_score > 1.0f) {
                    class_score = sigmoid(class_score);
                }
                const float combined = objectness * class_score;
                if (combined > best_score) {
                    best_score = combined;
                    class_id = static_cast<int>(attribute - 5);
                }
            }
        }

        if (objectness < 0.0f || objectness > 1.0f) {
            objectness = sigmoid(objectness);
        }
        if (attributes == 6) {
            best_score = objectness;
        }
        if (best_score < threshold) {
            continue;
        }

        DetectionCandidate candidate;
        candidate.score = best_score;
        candidate.class_id = class_id;

        // If coordinates are not normalized, assume they are model-input pixels.
        const bool normalized = std::max({std::fabs(x), std::fabs(y), std::fabs(w_or_x2), std::fabs(h_or_y2)}) <= 2.0f;
        const float x_scale = normalized ? static_cast<float>(model_width) : 1.0f;
        const float y_scale = normalized ? static_cast<float>(model_height) : 1.0f;

        if (w_or_x2 > x && h_or_y2 > y) {
            candidate.x1 = x * x_scale;
            candidate.y1 = y * y_scale;
            candidate.x2 = w_or_x2 * x_scale;
            candidate.y2 = h_or_y2 * y_scale;
        } else {
            const float cx = x * x_scale;
            const float cy = y * y_scale;
            const float bw = w_or_x2 * x_scale;
            const float bh = h_or_y2 * y_scale;
            candidate.x1 = cx - bw * 0.5f;
            candidate.y1 = cy - bh * 0.5f;
            candidate.x2 = cx + bw * 0.5f;
            candidate.y2 = cy + bh * 0.5f;
        }

        // Convert from model/letterbox pixels back to original image normalized coordinates.
        const float inv_scale = letterbox.scale > 0.0f ? 1.0f / letterbox.scale : 1.0f;
        candidate.x1 = ((candidate.x1 - static_cast<float>(letterbox.pad_x)) * inv_scale) / static_cast<float>(image_width);
        candidate.y1 = ((candidate.y1 - static_cast<float>(letterbox.pad_y)) * inv_scale) / static_cast<float>(image_height);
        candidate.x2 = ((candidate.x2 - static_cast<float>(letterbox.pad_x)) * inv_scale) / static_cast<float>(image_width);
        candidate.y2 = ((candidate.y2 - static_cast<float>(letterbox.pad_y)) * inv_scale) / static_cast<float>(image_height);

        candidates.push_back(candidate);
    }

    std::sort(candidates.begin(), candidates.end(), [](const DetectionCandidate& a, const DetectionCandidate& b) {
        return a.score > b.score;
    });
    if (candidates.size() > 100) {
        candidates.resize(100);
    }
    add_detection_result(candidates, result);
}

bool append_gpu_provider(OrtSessionOptions* options, std::string* error) {
#if defined(__APPLE__)
    if (OrtSessionOptionsAppendExecutionProvider_CoreML) {
        OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CoreML(options, 0);
        if (!status) {
            return true;
        }
        *error = consume_status(status);
        return false;
    }
    *error = "ONNX Runtime CoreML execution provider is not available";
    return false;
#elif !defined(_WIN32)
    if (OrtSessionOptionsAppendExecutionProvider_CUDA) {
        OrtStatus* status = OrtSessionOptionsAppendExecutionProvider_CUDA(options, 0);
        if (!status) {
            return true;
        }
        *error = consume_status(status);
        return false;
    }
    *error = "ONNX Runtime CUDA execution provider is not available";
    return false;
#else
    *error = "GPU execution provider is not configured for this platform";
    return false;
#endif
}

}  // namespace

struct EssentialOnnxSession {
    OrtEnv* env = nullptr;
    OrtSession* session = nullptr;
    OrtSessionOptions* session_options = nullptr;
    OrtMemoryInfo* memory_info = nullptr;
    std::string model_path;
    int input_width = kDefaultInputWidth;
    int input_height = kDefaultInputHeight;
    int num_channels = kDefaultChannels;
    bool use_gpu = false;
    std::string input_name;
    std::vector<std::string> output_names;
    std::vector<int64_t> input_shape;
    EssentialVisionTaskType task_type = ESSENTIAL_VISION_CLASSIFICATION;
    float confidence_threshold = kDefaultConfidenceThreshold;
    int top_k = kDefaultTopK;
    std::mutex run_mutex;

    ~EssentialOnnxSession() {
        const OrtApi* api = ort_api();
        if (memory_info) {
            api->ReleaseMemoryInfo(memory_info);
        }
        if (session) {
            api->ReleaseSession(session);
        }
        if (session_options) {
            api->ReleaseSessionOptions(session_options);
        }
        if (env) {
            api->ReleaseEnv(env);
        }
    }
};

extern "C" {

EssentialVisionSessionHandle essential_vision_create_onnx_session(
    const char* model_path,
    int use_gpu);
int essential_vision_onnx_run_inference(
    EssentialVisionSessionHandle session,
    const EssentialImage* image,
    EssentialVisionResult** result_out);
void essential_vision_destroy_onnx_session(EssentialVisionSessionHandle session);

#if defined(ESSENTIAL_VISION_STANDALONE_ONNX)
struct EssentialVisionContext {
    std::string last_error;
};

EssentialVisionContextHandle essential_vision_create_context() {
    return reinterpret_cast<EssentialVisionContextHandle>(new EssentialVisionContext());
}

void essential_vision_destroy_context(EssentialVisionContextHandle ctx) {
    delete reinterpret_cast<EssentialVisionContext*>(ctx);
}

EssentialVisionSessionHandle essential_vision_create_session(
    EssentialVisionContextHandle,
    const EssentialVisionConfig* config) {
    if (!config) {
        set_last_error("Vision config is null");
        return nullptr;
    }
    return essential_vision_create_onnx_session(
        config->model_path,
        config->use_gpu ? 1 : 0);
}

void essential_vision_destroy_session(EssentialVisionSessionHandle session) {
    essential_vision_destroy_onnx_session(session);
}

EssentialVisionResult* essential_vision_run_inference(
    EssentialVisionSessionHandle session,
    const EssentialImage* image) {
    EssentialVisionResult* result = nullptr;
    if (essential_vision_onnx_run_inference(session, image, &result) != 0 && !result) {
        return make_error_result(g_last_error.empty() ? "ONNX vision inference failed" : g_last_error);
    }
    return result;
}

void essential_vision_free_result(EssentialVisionResult* result) {
    if (!result) return;
    for (size_t i = 0; i < result->num_classifications; ++i) {
        std::free(result->classifications[i].label);
        std::free(result->classifications[i].label_id);
    }
    delete[] result->classifications;
    for (size_t i = 0; i < result->num_detections; ++i) {
        std::free(result->detections[i].label);
        std::free(result->detections[i].label_id);
    }
    delete[] result->detections;
    for (size_t i = 0; i < result->num_text_regions; ++i) {
        std::free(result->text_regions[i].text);
    }
    delete[] result->text_regions;
    std::free(result->caption_text);
    std::free(result->error_message);
    delete result;
}

const char* essential_vision_get_last_error() {
    return g_last_error.empty() ? nullptr : g_last_error.c_str();
}
#endif

EssentialVisionSessionHandle essential_vision_create_onnx_session(
    const char* model_path,
    int use_gpu) {
    if (!model_path || model_path[0] == '\0') {
        set_last_error("Model path is empty");
        return nullptr;
    }

    const OrtApi* api = ort_api();
    std::unique_ptr<EssentialOnnxSession> session(new EssentialOnnxSession());
    session->model_path = model_path;
    session->use_gpu = use_gpu != 0;

    std::string error;
    if (!check_status(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "essential_vision_onnx", &session->env), &error)) {
        return nullptr;
    }
    if (!check_status(api->CreateSessionOptions(&session->session_options), &error)) {
        return nullptr;
    }
    check_status(api->SetIntraOpNumThreads(session->session_options, 1), nullptr);
    check_status(api->SetSessionGraphOptimizationLevel(session->session_options, ORT_ENABLE_ALL), nullptr);

    if (session->use_gpu) {
        std::string provider_error;
        if (!append_gpu_provider(session->session_options, &provider_error)) {
            // Keep the runtime usable on-device: record the provider failure and fall back to CPU.
            set_last_error(provider_error + "; falling back to CPU execution");
            session->use_gpu = false;
        }
    }

    if (!check_status(api->CreateSession(session->env, model_path, session->session_options, &session->session), &error)) {
        return nullptr;
    }
    if (!check_status(api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &session->memory_info), &error)) {
        return nullptr;
    }

    OrtAllocator* allocator = nullptr;
    if (!check_status(api->GetAllocatorWithDefaultOptions(&allocator), &error)) {
        return nullptr;
    }

    size_t input_count = 0;
    size_t output_count = 0;
    if (!check_status(api->SessionGetInputCount(session->session, &input_count), &error) || input_count == 0) {
        set_last_error(input_count == 0 ? "ONNX model has no inputs" : error);
        return nullptr;
    }
    if (!check_status(api->SessionGetOutputCount(session->session, &output_count), &error) || output_count == 0) {
        set_last_error(output_count == 0 ? "ONNX model has no outputs" : error);
        return nullptr;
    }

    session->input_name = get_io_name(session->session, 0, true, allocator);
    if (session->input_name.empty()) {
        set_last_error("Failed to read ONNX input name");
        return nullptr;
    }
    session->output_names.reserve(output_count);
    for (size_t i = 0; i < output_count; ++i) {
        std::string output_name = get_io_name(session->session, i, false, allocator);
        if (!output_name.empty()) {
            session->output_names.push_back(std::move(output_name));
        }
    }
    if (session->output_names.empty()) {
        set_last_error("Failed to read ONNX output names");
        return nullptr;
    }

    session->input_shape = get_input_shape(session->session, 0);
    if (session->input_shape.size() == 4) {
        const bool nchw = session->input_shape[1] == 1 || session->input_shape[1] == 3 || session->input_shape[1] == 4;
        if (nchw) {
            session->num_channels = session->input_shape[1] > 0 ? static_cast<int>(session->input_shape[1]) : kDefaultChannels;
            session->input_height = session->input_shape[2] > 0 ? static_cast<int>(session->input_shape[2]) : kDefaultInputHeight;
            session->input_width = session->input_shape[3] > 0 ? static_cast<int>(session->input_shape[3]) : kDefaultInputWidth;
        } else {
            session->input_height = session->input_shape[1] > 0 ? static_cast<int>(session->input_shape[1]) : kDefaultInputHeight;
            session->input_width = session->input_shape[2] > 0 ? static_cast<int>(session->input_shape[2]) : kDefaultInputWidth;
            session->num_channels = session->input_shape[3] > 0 ? static_cast<int>(session->input_shape[3]) : kDefaultChannels;
        }
    }

    return reinterpret_cast<EssentialVisionSessionHandle>(session.release());
}

int essential_vision_onnx_run_inference(
    EssentialVisionSessionHandle session_handle,
    const EssentialImage* image,
    EssentialVisionResult** result_out) {
    if (!result_out) {
        set_last_error("result_out is null");
        return -1;
    }
    *result_out = nullptr;

    auto* session = reinterpret_cast<EssentialOnnxSession*>(session_handle);
    if (!session || !session->session) {
        *result_out = make_error_result("ONNX session is not initialized");
        return -1;
    }

    std::string error;
    if (!validate_image(image, &error)) {
        *result_out = make_error_result(error);
        return -1;
    }

    auto start_time = std::chrono::high_resolution_clock::now();
    EssentialVisionResult* result = make_empty_result();
    *result_out = result;

    std::lock_guard<std::mutex> lock(session->run_mutex);

    LetterboxInfo letterbox;
    std::vector<float> resized = preprocess_image_resize(
        image,
        session->input_width,
        session->input_height,
        &letterbox);
    preprocess_image_normalize(&resized, false);
    const int input_channels = (session->num_channels == 1 || session->num_channels == 4)
        ? session->num_channels
        : kDefaultChannels;
    std::vector<float> input_hwc = adapt_hwc_channels(
        resized,
        session->input_width,
        session->input_height,
        input_channels);
    std::vector<float> input_data = hwc_to_chw(
        input_hwc,
        session->input_width,
        session->input_height,
        input_channels);

    std::vector<int64_t> input_shape = session->input_shape;
    if (input_shape.size() != 4) {
        input_shape = {1, input_channels, session->input_height, session->input_width};
    }
    for (int64_t& dim : input_shape) {
        if (dim <= 0) {
            dim = 1;
        }
    }
    if (input_shape.size() == 4) {
        const bool nchw = input_shape[1] == 1 || input_shape[1] == 3 || input_shape[1] == 4;
        if (nchw) {
            input_shape[0] = 1;
            input_shape[1] = input_channels;
            input_shape[2] = session->input_height;
            input_shape[3] = session->input_width;
        } else {
            input_shape[0] = 1;
            input_shape[1] = session->input_height;
            input_shape[2] = session->input_width;
            input_shape[3] = input_channels;
            input_data = std::move(input_hwc);
        }
    }

    OrtValue* input_tensor = nullptr;
    const size_t input_bytes = input_data.size() * sizeof(float);
    if (!check_status(ort_api()->CreateTensorWithDataAsOrtValue(
            session->memory_info,
            input_data.data(),
            input_bytes,
            input_shape.data(),
            input_shape.size(),
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &input_tensor), &error)) {
        result->error_message = duplicate_string(error);
        return -1;
    }
    OrtValueHolder input_holder(input_tensor);

    std::vector<const char*> input_names = {session->input_name.c_str()};
    std::vector<const char*> output_names;
    output_names.reserve(session->output_names.size());
    for (const std::string& name : session->output_names) {
        output_names.push_back(name.c_str());
    }
    std::vector<OrtValue*> output_tensors(output_names.size(), nullptr);

    if (!check_status(ort_api()->Run(
            session->session,
            nullptr,
            input_names.data(),
            reinterpret_cast<const OrtValue* const*>(&input_holder.value),
            input_names.size(),
            output_names.data(),
            output_names.size(),
            output_tensors.data()), &error)) {
        result->error_message = duplicate_string(error);
        return -1;
    }

    std::vector<OrtValueHolder> output_holders;
    output_holders.reserve(output_tensors.size());
    for (OrtValue* output : output_tensors) {
        output_holders.emplace_back(output);
    }

    if (!output_tensors.empty()) {
        int is_tensor = 0;
        if (!check_status(ort_api()->IsTensor(output_tensors[0], &is_tensor), &error) || !is_tensor) {
            result->error_message = duplicate_string(is_tensor ? error : "ONNX output is not a tensor");
            return -1;
        }

        void* raw_data = nullptr;
        if (!check_status(ort_api()->GetTensorMutableData(output_tensors[0], &raw_data), &error)) {
            result->error_message = duplicate_string(error);
            return -1;
        }

        std::vector<int64_t> output_shape = get_value_shape(output_tensors[0], &error);
        if (!error.empty()) {
            result->error_message = duplicate_string(error);
            return -1;
        }

        const size_t output_count = shape_element_count(output_shape);
        const float* output_data = static_cast<const float*>(raw_data);
        const bool looks_like_detection =
            (output_shape.size() == 3 && std::min<int64_t>(output_shape[1], output_shape[2]) >= 6) ||
            (output_shape.size() == 2 && output_shape[1] >= 6);
        const bool looks_like_box_output = !output_shape.empty() && output_shape.back() == 4 &&
            output_tensors.size() >= 3;

        if (looks_like_box_output) {
            void* raw_scores = nullptr;
            void* raw_classes = nullptr;
            std::vector<int64_t> score_shape = get_value_shape(output_tensors[1], &error);
            std::vector<int64_t> class_shape = get_value_shape(output_tensors[2], &error);
            if (!error.empty() ||
                !check_status(ort_api()->GetTensorMutableData(output_tensors[1], &raw_scores), &error) ||
                !check_status(ort_api()->GetTensorMutableData(output_tensors[2], &raw_classes), &error)) {
                result->error_message = duplicate_string(error.empty() ? "Failed to read detection outputs" : error);
                return -1;
            }
            session->task_type = ESSENTIAL_VISION_DETECTION;
            parse_detection_triplet(
                output_data,
                output_shape,
                static_cast<const float*>(raw_scores),
                score_shape,
                static_cast<const float*>(raw_classes),
                class_shape,
                session->confidence_threshold,
                session->input_width,
                session->input_height,
                image->width,
                image->height,
                letterbox,
                result);
        } else if (looks_like_detection) {
            session->task_type = ESSENTIAL_VISION_DETECTION;
            parse_detections(
                output_data,
                output_shape,
                session->confidence_threshold,
                session->input_width,
                session->input_height,
                image->width,
                image->height,
                letterbox,
                result);
        } else {
            session->task_type = ESSENTIAL_VISION_CLASSIFICATION;
            parse_classification(output_data, output_count, session->top_k, result);
        }
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    result->latency_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count());

    return result->error_message ? -1 : 0;
}

void essential_vision_destroy_onnx_session(EssentialVisionSessionHandle session_handle) {
    auto* session = reinterpret_cast<EssentialOnnxSession*>(session_handle);
    delete session;
}

int essential_vision_init_onnx(
    EssentialVisionContextHandle,
    const char* model_path,
    bool use_gpu) {
    EssentialVisionSessionHandle session = essential_vision_create_onnx_session(
        model_path,
        use_gpu ? 1 : 0);
    if (!session) {
        return -1;
    }
    essential_vision_destroy_onnx_session(session);
    return 0;
}

const char* essential_vision_onnx_get_last_error() {
    return g_last_error.empty() ? nullptr : g_last_error.c_str();
}

}  // extern "C"
