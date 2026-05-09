#include "essential_audio_runtime.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

#if __has_include("whisper.h")
#include "whisper.h"
#define ESSENTIAL_AUDIO_HAS_WHISPER 1
#else
#define ESSENTIAL_AUDIO_HAS_WHISPER 0
struct whisper_context;
#endif

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

constexpr int kWhisperSampleRate = 16000;
constexpr float kVadThreshold = 0.012f;
constexpr int kStreamingWindowMs = 2200;

thread_local std::string g_last_error;

char* copy_string(const std::string& value) {
    char* out = static_cast<char*>(std::malloc(value.size() + 1));
    if (!out) {
        return nullptr;
    }
    std::memcpy(out, value.c_str(), value.size() + 1);
    return out;
}

void set_error(const std::string& message) {
    g_last_error = message;
}

float rms_energy(const std::vector<float>& samples) {
    if (samples.empty()) {
        return 0.0f;
    }
    double sum = 0.0;
    for (float sample : samples) {
        sum += static_cast<double>(sample) * static_cast<double>(sample);
    }
    return static_cast<float>(std::sqrt(sum / static_cast<double>(samples.size())));
}

std::vector<float> downmix_to_mono(const EssentialAudioBuffer* audio) {
    if (!audio || !audio->samples || audio->num_samples <= 0 || audio->channels <= 0) {
        return {};
    }
    const int frames = audio->num_samples / audio->channels;
    std::vector<float> mono(static_cast<size_t>(frames));
    for (int frame = 0; frame < frames; ++frame) {
        float sum = 0.0f;
        for (int channel = 0; channel < audio->channels; ++channel) {
            sum += audio->samples[frame * audio->channels + channel];
        }
        mono[frame] = std::clamp(sum / static_cast<float>(audio->channels), -1.0f, 1.0f);
    }
    return mono;
}

std::vector<float> resample_linear(
    const std::vector<float>& input,
    int source_rate,
    int target_rate) {
    if (input.empty() || source_rate <= 0 || target_rate <= 0) {
        return {};
    }
    if (source_rate == target_rate) {
        return input;
    }
    const double ratio = static_cast<double>(source_rate) / static_cast<double>(target_rate);
    const size_t out_count = static_cast<size_t>(std::ceil(static_cast<double>(input.size()) / ratio));
    std::vector<float> output(out_count);
    for (size_t i = 0; i < out_count; ++i) {
        const double src = static_cast<double>(i) * ratio;
        const size_t left = std::min(static_cast<size_t>(src), input.size() - 1);
        const size_t right = std::min(left + 1, input.size() - 1);
        const float t = static_cast<float>(src - static_cast<double>(left));
        output[i] = input[left] + (input[right] - input[left]) * t;
    }
    return output;
}

std::vector<float> prepare_whisper_audio(const EssentialAudioBuffer* audio) {
    return resample_linear(downmix_to_mono(audio), audio ? audio->sample_rate : 0, kWhisperSampleRate);
}

bool read_wav_file(const char* path, EssentialAudioBuffer* out, std::vector<float>* storage) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        set_error("Failed to open audio file");
        return false;
    }

    char riff[4] = {};
    uint32_t riff_size = 0;
    char wave[4] = {};
    file.read(riff, 4);
    file.read(reinterpret_cast<char*>(&riff_size), 4);
    file.read(wave, 4);
    if (std::strncmp(riff, "RIFF", 4) != 0 || std::strncmp(wave, "WAVE", 4) != 0) {
        set_error("Only RIFF/WAVE PCM files are supported by the built-in file reader");
        return false;
    }

    uint16_t format = 0;
    uint16_t channels = 0;
    uint32_t sample_rate = 0;
    uint16_t bits_per_sample = 0;
    std::vector<uint8_t> pcm;

    while (file && !file.eof()) {
        char chunk_id[4] = {};
        uint32_t chunk_size = 0;
        file.read(chunk_id, 4);
        file.read(reinterpret_cast<char*>(&chunk_size), 4);
        if (!file) {
            break;
        }
        if (std::strncmp(chunk_id, "fmt ", 4) == 0) {
            file.read(reinterpret_cast<char*>(&format), 2);
            file.read(reinterpret_cast<char*>(&channels), 2);
            file.read(reinterpret_cast<char*>(&sample_rate), 4);
            file.seekg(6, std::ios::cur);
            file.read(reinterpret_cast<char*>(&bits_per_sample), 2);
            if (chunk_size > 16) {
                file.seekg(chunk_size - 16, std::ios::cur);
            }
        } else if (std::strncmp(chunk_id, "data", 4) == 0) {
            pcm.resize(chunk_size);
            file.read(reinterpret_cast<char*>(pcm.data()), chunk_size);
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    if (format != 1 || (bits_per_sample != 16 && bits_per_sample != 32) || channels == 0 || sample_rate == 0 || pcm.empty()) {
        set_error("Unsupported WAV encoding; expected PCM16 or PCM32 float-compatible data");
        return false;
    }

    const size_t sample_count = bits_per_sample == 16 ? pcm.size() / 2 : pcm.size() / 4;
    storage->resize(sample_count);
    if (bits_per_sample == 16) {
        const auto* values = reinterpret_cast<const int16_t*>(pcm.data());
        for (size_t i = 0; i < sample_count; ++i) {
            (*storage)[i] = static_cast<float>(values[i]) / 32768.0f;
        }
    } else {
        std::memcpy(storage->data(), pcm.data(), pcm.size());
    }

    out->samples = storage->data();
    out->num_samples = static_cast<int>(storage->size());
    out->sample_rate = static_cast<int>(sample_rate);
    out->channels = static_cast<int>(channels);
    out->format = sample_rate <= 16000 ? ESSENTIAL_AUDIO_PCM_16K : sample_rate <= 22050 ? ESSENTIAL_AUDIO_PCM_22K : ESSENTIAL_AUDIO_PCM_44K;
    return true;
}

void set_context_error(EssentialAudioContext* ctx, const std::string& message) {
    set_error(message);
    if (ctx) {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        ctx->last_error = message;
    }
}

int make_single_segment(
    const std::string& text,
    double start,
    double end,
    bool is_final,
    EssentialSttSegment** segments,
    int* num_segments) {
    *segments = static_cast<EssentialSttSegment*>(std::calloc(1, sizeof(EssentialSttSegment)));
    if (!*segments) {
        set_error("Failed to allocate STT segment");
        return -1;
    }
    (*segments)[0].text = copy_string(text);
    (*segments)[0].confidence = 1.0f;
    (*segments)[0].start_time = start;
    (*segments)[0].end_time = end;
    (*segments)[0].is_final = is_final;
    *num_segments = 1;
    return 0;
}

int run_whisper(
    EssentialAudioSession* session,
    const EssentialAudioBuffer* audio,
    EssentialSttSegment** segments,
    int* num_segments) {
    *segments = nullptr;
    *num_segments = 0;

    std::vector<float> pcm = prepare_whisper_audio(audio);
    if (pcm.empty()) {
        set_context_error(session->owner, "Audio buffer is empty or invalid");
        return -1;
    }
    if (rms_energy(pcm) < kVadThreshold) {
        return 0;
    }

#if ESSENTIAL_AUDIO_HAS_WHISPER
    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.translate = session->translate;
    params.language = session->language == "auto" ? nullptr : session->language.c_str();
    params.no_context = true;
    params.single_segment = false;

    if (whisper_full(session->whisper, params, pcm.data(), static_cast<int>(pcm.size())) != 0) {
        set_context_error(session->owner, "Whisper inference failed");
        return -1;
    }

    const int count = whisper_full_n_segments(session->whisper);
    if (count <= 0) {
        return 0;
    }
    auto* out = static_cast<EssentialSttSegment*>(std::calloc(static_cast<size_t>(count), sizeof(EssentialSttSegment)));
    if (!out) {
        set_context_error(session->owner, "Failed to allocate Whisper segments");
        return -1;
    }
    for (int i = 0; i < count; ++i) {
        const char* text = whisper_full_get_segment_text(session->whisper, i);
        const int64_t t0 = whisper_full_get_segment_t0(session->whisper, i);
        const int64_t t1 = whisper_full_get_segment_t1(session->whisper, i);
        out[i].text = copy_string(text ? text : "");
        out[i].start_time = static_cast<double>(t0) / 100.0;
        out[i].end_time = static_cast<double>(t1) / 100.0;
        out[i].confidence = 1.0f - whisper_full_get_segment_no_speech_prob(session->whisper, i);
        out[i].is_final = true;
    }
    *segments = out;
    *num_segments = count;
    return 0;
#else
    (void)make_single_segment;
    set_context_error(session->owner, "Whisper support is not compiled in; add whisper.h and link whisper.cpp");
    return -1;
#endif
}

}  // namespace

extern "C" {

void essential_audio_set_last_error(const char* message) {
    set_error(message ? message : "");
}

EssentialAudioContextHandle essential_audio_create_context() {
    return reinterpret_cast<EssentialAudioContextHandle>(new EssentialAudioContext());
}

void essential_audio_destroy_context(EssentialAudioContextHandle ctx) {
    delete reinterpret_cast<EssentialAudioContext*>(ctx);
}

EssentialAudioSessionHandle essential_audio_create_stt_session(
    EssentialAudioContextHandle ctx_handle,
    const char* model_path,
    const char* language,
    bool translate) {
    auto* ctx = reinterpret_cast<EssentialAudioContext*>(ctx_handle);
    if (!model_path || model_path[0] == '\0') {
        set_context_error(ctx, "Whisper model path is empty");
        return nullptr;
    }

    std::unique_ptr<EssentialAudioSession> session(new EssentialAudioSession());
    session->kind = SessionKind::stt;
    session->owner = ctx;
    session->model_path = model_path;
    session->language = language && language[0] != '\0' ? language : "auto";
    session->translate = translate;

#if ESSENTIAL_AUDIO_HAS_WHISPER
    whisper_context_params cparams = whisper_context_default_params();
    session->whisper = whisper_init_from_file_with_params(model_path, cparams);
    if (!session->whisper) {
        set_context_error(ctx, "Failed to load Whisper model");
        return nullptr;
    }
#else
    set_context_error(ctx, "Whisper support is not compiled in; session created as unavailable");
#endif
    return reinterpret_cast<EssentialAudioSessionHandle>(session.release());
}

void essential_audio_destroy_session(EssentialAudioSessionHandle handle) {
    auto* session = reinterpret_cast<EssentialAudioSession*>(handle);
    if (!session) {
        return;
    }
    session->streaming = false;
    if (session->stream_thread.joinable()) {
        session->stream_thread.join();
    }
#if ESSENTIAL_AUDIO_HAS_WHISPER
    if (session->whisper) {
        whisper_free(session->whisper);
    }
#endif
    std::free(session->tts_config.voice_id);
    delete session;
}

int essential_audio_stt_process_chunk(
    EssentialAudioSessionHandle handle,
    const EssentialAudioBuffer* audio,
    EssentialSttSegment** segments,
    int* num_segments) {
    if (!segments || !num_segments) {
        set_error("segments and num_segments are required");
        return -1;
    }
    auto* session = reinterpret_cast<EssentialAudioSession*>(handle);
    if (!session || session->kind != SessionKind::stt) {
        set_error("Invalid STT session");
        return -1;
    }
    std::lock_guard<std::mutex> lock(session->mutex);
    return run_whisper(session, audio, segments, num_segments);
}

int essential_audio_stt_process_file(
    EssentialAudioSessionHandle handle,
    const char* audio_file_path,
    char** full_text,
    EssentialSttSegment** segments,
    int* num_segments) {
    if (!full_text || !segments || !num_segments) {
        set_error("full_text, segments, and num_segments are required");
        return -1;
    }
    *full_text = nullptr;
    EssentialAudioBuffer audio{};
    std::vector<float> storage;
    if (!read_wav_file(audio_file_path, &audio, &storage)) {
        return -1;
    }
    const int rc = essential_audio_stt_process_chunk(handle, &audio, segments, num_segments);
    if (rc != 0) {
        return rc;
    }
    std::string text;
    for (int i = 0; i < *num_segments; ++i) {
        if (i > 0) {
            text.push_back(' ');
        }
        text += (*segments)[i].text ? (*segments)[i].text : "";
    }
    *full_text = copy_string(text);
    return *full_text ? 0 : -1;
}

int essential_audio_stt_start_stream(
    EssentialAudioSessionHandle handle,
    EssentialSttCallback callback,
    void* user_data) {
    auto* session = reinterpret_cast<EssentialAudioSession*>(handle);
    if (!session || session->kind != SessionKind::stt || !callback) {
        set_error("Invalid streaming STT arguments");
        return -1;
    }
    if (session->streaming.exchange(true)) {
        return 0;
    }
    session->callback = callback;
    session->callback_user_data = user_data;
    session->stream_thread = std::thread([session]() {
        const int window_samples = kWhisperSampleRate * kStreamingWindowMs / 1000;
        while (session->streaming) {
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            std::vector<float> window;
            {
                std::lock_guard<std::mutex> lock(session->mutex);
                if (static_cast<int>(session->stream_buffer.size()) < window_samples) {
                    continue;
                }
                window.swap(session->stream_buffer);
            }
            EssentialAudioBuffer audio{};
            audio.samples = window.data();
            audio.num_samples = static_cast<int>(window.size());
            audio.sample_rate = kWhisperSampleRate;
            audio.channels = 1;
            audio.format = ESSENTIAL_AUDIO_PCM_16K;
            EssentialSttSegment* segments = nullptr;
            int num_segments = 0;
            if (run_whisper(session, &audio, &segments, &num_segments) == 0) {
                std::string final_text;
                for (int i = 0; i < num_segments; ++i) {
                    final_text += segments[i].text ? segments[i].text : "";
                }
                if (!final_text.empty()) {
                    session->callback(nullptr, final_text.c_str(), true, session->callback_user_data);
                }
                essential_audio_free_segments(segments, num_segments);
            }
        }
    });
    return 0;
}

int essential_audio_stt_stop_stream(EssentialAudioSessionHandle handle) {
    auto* session = reinterpret_cast<EssentialAudioSession*>(handle);
    if (!session) {
        set_error("Invalid STT session");
        return -1;
    }
    session->streaming = false;
    if (session->stream_thread.joinable()) {
        session->stream_thread.join();
    }
    return 0;
}

void essential_audio_free_buffer(EssentialAudioBuffer* buffer) {
    if (!buffer) {
        return;
    }
    std::free(buffer->samples);
    std::free(buffer);
}

void essential_audio_free_segments(EssentialSttSegment* segments, int num) {
    if (!segments) {
        return;
    }
    for (int i = 0; i < num; ++i) {
        std::free(segments[i].text);
    }
    std::free(segments);
}

void essential_audio_free_string(char* str) {
    std::free(str);
}

const char* essential_audio_get_last_error() {
    return g_last_error.empty() ? nullptr : g_last_error.c_str();
}

}  // extern "C"
