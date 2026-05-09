#ifndef ESSENTIAL_AUDIO_RUNTIME_H
#define ESSENTIAL_AUDIO_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ESSENTIAL_AUDIO_PCM_16K = 0,
    ESSENTIAL_AUDIO_PCM_22K = 1,
    ESSENTIAL_AUDIO_PCM_44K = 2,
    ESSENTIAL_AUDIO_OPUS = 3,
    ESSENTIAL_AUDIO_AAC = 4,
} EssentialAudioFormat;

typedef enum {
    ESSENTIAL_AUDIO_STT = 0,
    ESSENTIAL_AUDIO_TTS = 1,
    ESSENTIAL_AUDIO_VOICE_COMMAND = 2,
    ESSENTIAL_AUDIO_CLASSIFICATION = 3,
} EssentialAudioTaskType;

typedef struct {
    float* samples;
    int num_samples;
    int sample_rate;
    EssentialAudioFormat format;
    int channels;
} EssentialAudioBuffer;

typedef struct {
    char* text;
    float confidence;
    double start_time;
    double end_time;
    bool is_final;
} EssentialSttSegment;

typedef struct {
    char* voice_id;
    float speed;
    float pitch;
    int sample_rate;
} EssentialTtsConfig;

typedef struct EssentialAudioContext* EssentialAudioContextHandle;
typedef struct EssentialAudioSession* EssentialAudioSessionHandle;

EssentialAudioContextHandle essential_audio_create_context();
void essential_audio_destroy_context(EssentialAudioContextHandle ctx);

EssentialAudioSessionHandle essential_audio_create_stt_session(
    EssentialAudioContextHandle ctx,
    const char* model_path,
    const char* language,
    bool translate);

EssentialAudioSessionHandle essential_audio_create_tts_session(
    EssentialAudioContextHandle ctx,
    const char* model_path,
    EssentialTtsConfig* config);

void essential_audio_destroy_session(EssentialAudioSessionHandle session);

int essential_audio_stt_process_chunk(
    EssentialAudioSessionHandle session,
    const EssentialAudioBuffer* audio,
    EssentialSttSegment** segments,
    int* num_segments);

int essential_audio_stt_process_file(
    EssentialAudioSessionHandle session,
    const char* audio_file_path,
    char** full_text,
    EssentialSttSegment** segments,
    int* num_segments);

int essential_audio_tts_synthesize(
    EssentialAudioSessionHandle session,
    const char* text,
    EssentialAudioBuffer** output_audio);

typedef void (*EssentialSttCallback)(
    const char* partial_text,
    const char* final_text,
    bool is_endpoint,
    void* user_data);

int essential_audio_stt_start_stream(
    EssentialAudioSessionHandle session,
    EssentialSttCallback callback,
    void* user_data);

int essential_audio_stt_stop_stream(EssentialAudioSessionHandle session);

void essential_audio_free_buffer(EssentialAudioBuffer* buffer);
void essential_audio_free_segments(EssentialSttSegment* segments, int num);
void essential_audio_free_string(char* str);

const char* essential_audio_get_last_error();

#ifdef __cplusplus
}
#endif

#endif
