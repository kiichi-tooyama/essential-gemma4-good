#include "essential_audio_runtime.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#if __has_include(<onnxruntime_c_api.h>)
#include <onnxruntime_c_api.h>
#define ESSENTIAL_AUDIO_HAS_ONNX 1
#else
#define ESSENTIAL_AUDIO_HAS_ONNX 0
#endif

struct whisper_context;

enum class SessionKind {
    stt,
    tts,
};

struct EssentialAudioContext {
    std::mutex mutex;
    std::string last_error;
};

struct EssentialAudioSession {
    SessionKind kind = SessionKind::stt;
    EssentialAudioContext* owner = nullptr;
    std::mutex mutex;
    std::string model_path;
    std::string language = "auto";
    bool translate = false;
    whisper_context* whisper = nullptr;
    EssentialTtsConfig tts_config{};
    std::atomic<bool> streaming{false};
    std::thread stream_thread;
    EssentialSttCallback callback = nullptr;
    void* callback_user_data = nullptr;
    std::vector<float> stream_buffer;
};

namespace {

constexpr float kPi = 3.14159265358979323846f;
thread_local std::string g_tts_error;

char* copy_string(const std::string& value) {
    char* out = static_cast<char*>(std::malloc(value.size() + 1));
    if (!out) {
        return nullptr;
    }
    std::memcpy(out, value.c_str(), value.size() + 1);
    return out;
}

void set_error(EssentialAudioContext* ctx, const std::string& message) {
    g_tts_error = message;
    if (ctx) {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        ctx->last_error = message;
    }
}

std::string normalize_text(const char* text) {
    if (!text) {
        return {};
    }
    std::string input(text);
    std::string output;
    bool last_space = false;
    for (char ch : input) {
        unsigned char c = static_cast<unsigned char>(ch);
        if (std::isspace(c)) {
            if (!last_space) {
                output.push_back(' ');
            }
            last_space = true;
        } else {
            output.push_back(static_cast<char>(std::tolower(c)));
            last_space = false;
        }
    }
    while (!output.empty() && output.front() == ' ') {
        output.erase(output.begin());
    }
    while (!output.empty() && output.back() == ' ') {
        output.pop_back();
    }
    return output;
}

std::string expand_numbers(const std::string& text) {
    static const char* digits[] = {
        "zero", "one", "two", "three", "four",
        "five", "six", "seven", "eight", "nine",
    };
    std::string output;
    for (char ch : text) {
        if (ch >= '0' && ch <= '9') {
            if (!output.empty() && output.back() != ' ') {
                output.push_back(' ');
            }
            output += digits[ch - '0'];
            output.push_back(' ');
        } else {
            output.push_back(ch);
        }
    }
    return output;
}

std::vector<std::string> text_to_phonemes(const std::string& text) {
    static const std::unordered_map<char, const char*> phones = {
        {'a', "AH"}, {'b', "B"}, {'c', "K"}, {'d', "D"}, {'e', "EH"},
        {'f', "F"}, {'g', "G"}, {'h', "HH"}, {'i', "IY"}, {'j', "JH"},
        {'k', "K"}, {'l', "L"}, {'m', "M"}, {'n', "N"}, {'o', "OW"},
        {'p', "P"}, {'q', "K"}, {'r', "R"}, {'s', "S"}, {'t', "T"},
        {'u', "UW"}, {'v', "V"}, {'w', "W"}, {'x', "KS"}, {'y', "Y"},
        {'z', "Z"},
    };
    std::vector<std::string> result;
    for (char ch : text) {
        if (ch == ' ') {
            result.emplace_back("SP");
            continue;
        }
        const auto it = phones.find(ch);
        if (it != phones.end()) {
            result.emplace_back(it->second);
        } else if (ch == '.' || ch == ',' || ch == '?' || ch == '!') {
            result.emplace_back("PAUSE");
        }
    }
    return result;
}

float phone_frequency(const std::string& phone, float pitch) {
    static const std::unordered_map<std::string, float> base = {
        {"AH", 180.0f}, {"EH", 220.0f}, {"IY", 260.0f}, {"OW", 200.0f}, {"UW", 170.0f},
        {"B", 130.0f}, {"D", 150.0f}, {"F", 320.0f}, {"G", 145.0f}, {"HH", 280.0f},
        {"JH", 210.0f}, {"K", 155.0f}, {"L", 190.0f}, {"M", 120.0f}, {"N", 125.0f},
        {"P", 135.0f}, {"R", 175.0f}, {"S", 360.0f}, {"T", 160.0f}, {"V", 240.0f},
        {"W", 165.0f}, {"Y", 255.0f}, {"KS", 340.0f},
    };
    const auto it = base.find(phone);
    const float value = it == base.end() ? 180.0f : it->second;
    return value * std::pow(2.0f, pitch * 0.35f);
}

void append_phone_wave(
    std::vector<float>* audio,
    const std::string& phone,
    int sample_rate,
    float speed,
    float pitch) {
    const float safe_speed = std::clamp(speed, 0.5f, 2.0f);
    const int samples = phone == "SP" || phone == "PAUSE"
        ? static_cast<int>(sample_rate * (phone == "PAUSE" ? 0.18f : 0.06f) / safe_speed)
        : static_cast<int>(sample_rate * 0.085f / safe_speed);
    if (phone == "SP" || phone == "PAUSE") {
        audio->insert(audio->end(), static_cast<size_t>(samples), 0.0f);
        return;
    }

    const float f0 = phone_frequency(phone, pitch);
    const size_t offset = audio->size();
    audio->resize(offset + static_cast<size_t>(samples));
    for (int i = 0; i < samples; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(sample_rate);
        const float envelope = std::min(1.0f, std::min(i / 96.0f, (samples - i) / 160.0f));
        const float wave =
            0.55f * std::sin(2.0f * kPi * f0 * t) +
            0.25f * std::sin(2.0f * kPi * f0 * 2.0f * t) +
            0.10f * std::sin(2.0f * kPi * f0 * 3.0f * t);
        (*audio)[offset + static_cast<size_t>(i)] = std::clamp(wave * envelope * 0.35f, -1.0f, 1.0f);
    }
}

std::vector<float> synthesize_fallback(
    const std::vector<std::string>& phonemes,
    int sample_rate,
    float speed,
    float pitch) {
    std::vector<float> audio;
    audio.reserve(static_cast<size_t>(sample_rate * std::max<size_t>(1, phonemes.size())) / 10);
    for (const std::string& phone : phonemes) {
        append_phone_wave(&audio, phone, sample_rate, speed, pitch);
    }
    const int tail = sample_rate / 20;
    audio.insert(audio.end(), static_cast<size_t>(tail), 0.0f);
    return audio;
}

}  // namespace

extern "C" {

void essential_audio_set_last_error(const char* message);

EssentialAudioSessionHandle essential_audio_create_tts_session(
    EssentialAudioContextHandle ctx_handle,
    const char* model_path,
    EssentialTtsConfig* config) {
    auto* ctx = reinterpret_cast<EssentialAudioContext*>(ctx_handle);
    if (!model_path || model_path[0] == '\0') {
        set_error(ctx, "TTS model path is empty");
        essential_audio_set_last_error("TTS model path is empty");
        return nullptr;
    }

    std::unique_ptr<EssentialAudioSession> session(new EssentialAudioSession());
    session->kind = SessionKind::tts;
    session->owner = ctx;
    session->model_path = model_path;
    session->tts_config.voice_id = copy_string(config && config->voice_id ? config->voice_id : "default");
    session->tts_config.speed = config ? std::clamp(config->speed, 0.5f, 2.0f) : 1.0f;
    session->tts_config.pitch = config ? std::clamp(config->pitch, -1.0f, 1.0f) : 0.0f;
    session->tts_config.sample_rate = config && config->sample_rate > 0 ? config->sample_rate : 22050;

#if ESSENTIAL_AUDIO_HAS_ONNX
    // Production neural TTS integrations should bind model-specific input names
    // here. The deterministic fallback below keeps the C API usable for smoke tests
    // when a project-specific phonemizer/model config has not been packaged yet.
#else
    set_error(ctx, "ONNX Runtime headers are not available; using built-in fallback synthesizer");
    essential_audio_set_last_error("ONNX Runtime headers are not available; using built-in fallback synthesizer");
#endif
    return reinterpret_cast<EssentialAudioSessionHandle>(session.release());
}

int essential_audio_tts_synthesize(
    EssentialAudioSessionHandle handle,
    const char* text,
    EssentialAudioBuffer** output_audio) {
    if (!output_audio) {
        g_tts_error = "output_audio is required";
        essential_audio_set_last_error("output_audio is required");
        return -1;
    }
    *output_audio = nullptr;
    auto* session = reinterpret_cast<EssentialAudioSession*>(handle);
    if (!session || session->kind != SessionKind::tts) {
        g_tts_error = "Invalid TTS session";
        essential_audio_set_last_error("Invalid TTS session");
        return -1;
    }
    const std::string normalized = expand_numbers(normalize_text(text));
    if (normalized.empty()) {
        set_error(session->owner, "Text is empty");
        essential_audio_set_last_error("Text is empty");
        return -1;
    }

    std::lock_guard<std::mutex> lock(session->mutex);
    const std::vector<std::string> phonemes = text_to_phonemes(normalized);
    std::vector<float> waveform = synthesize_fallback(
        phonemes,
        session->tts_config.sample_rate,
        session->tts_config.speed,
        session->tts_config.pitch);
    if (waveform.empty()) {
        set_error(session->owner, "TTS synthesis produced no audio");
        essential_audio_set_last_error("TTS synthesis produced no audio");
        return -1;
    }

    auto* buffer = static_cast<EssentialAudioBuffer*>(std::calloc(1, sizeof(EssentialAudioBuffer)));
    if (!buffer) {
        set_error(session->owner, "Failed to allocate output audio buffer");
        essential_audio_set_last_error("Failed to allocate output audio buffer");
        return -1;
    }
    buffer->samples = static_cast<float*>(std::malloc(sizeof(float) * waveform.size()));
    if (!buffer->samples) {
        std::free(buffer);
        set_error(session->owner, "Failed to allocate output samples");
        essential_audio_set_last_error("Failed to allocate output samples");
        return -1;
    }
    std::memcpy(buffer->samples, waveform.data(), sizeof(float) * waveform.size());
    buffer->num_samples = static_cast<int>(waveform.size());
    buffer->sample_rate = session->tts_config.sample_rate;
    buffer->channels = 1;
    buffer->format = buffer->sample_rate <= 16000
        ? ESSENTIAL_AUDIO_PCM_16K
        : buffer->sample_rate <= 22050 ? ESSENTIAL_AUDIO_PCM_22K : ESSENTIAL_AUDIO_PCM_44K;
    *output_audio = buffer;
    return 0;
}

}  // extern "C"
