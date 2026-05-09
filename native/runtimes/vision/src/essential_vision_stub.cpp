#include "essential_vision_runtime.h"

#include <cstdlib>
#include <cstring>
#include <string>

namespace {
thread_local std::string g_error;

char* copy_string(const char* value) {
    if (!value) {
        return nullptr;
    }
    const size_t length = std::strlen(value);
    char* out = static_cast<char*>(std::malloc(length + 1));
    if (!out) {
        return nullptr;
    }
    std::memcpy(out, value, length + 1);
    return out;
}
}

struct EssentialVisionContext {
    std::string last_error;
};

struct EssentialVisionSession {
    int unused = 0;
};

extern "C" {

EssentialVisionContextHandle essential_vision_create_context() {
    g_error = "Essential vision runtime was built without ONNX Runtime or MediaPipe.";
    return nullptr;
}

void essential_vision_destroy_context(EssentialVisionContextHandle ctx) {
    delete reinterpret_cast<EssentialVisionContext*>(ctx);
}

EssentialVisionSessionHandle essential_vision_create_session(
    EssentialVisionContextHandle,
    const EssentialVisionConfig*) {
    g_error = "Essential vision runtime was built without ONNX Runtime or MediaPipe.";
    return nullptr;
}

void essential_vision_destroy_session(EssentialVisionSessionHandle session) {
    delete reinterpret_cast<EssentialVisionSession*>(session);
}

EssentialVisionResult* essential_vision_run_inference(
    EssentialVisionSessionHandle,
    const EssentialImage*) {
    auto* result = new EssentialVisionResult();
    std::memset(result, 0, sizeof(EssentialVisionResult));
    result->error_message = copy_string("Essential vision runtime is unavailable in this build.");
    return result;
}

void essential_vision_free_result(EssentialVisionResult* result) {
    if (!result) {
        return;
    }
    std::free(result->error_message);
    delete result;
}

const char* essential_vision_get_last_error() {
    return g_error.empty() ? nullptr : g_error.c_str();
}

int essential_vision_init_onnx(EssentialVisionContextHandle, const char*, bool) {
    g_error = "ONNX Runtime is not linked.";
    return -1;
}

}
