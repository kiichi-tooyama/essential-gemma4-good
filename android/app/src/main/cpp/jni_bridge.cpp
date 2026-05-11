#include <jni.h>

#include "essential_audio_runtime.h"
#include "essential_llama.h"

#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct request_state {
  essential_llama_engine * engine = nullptr;
};

struct cached_engine {
  explicit cached_engine(essential_llama_engine * engine_value) : engine(engine_value) {}

  ~cached_engine() {
    if (engine != nullptr) {
      essential_llama_engine_destroy(engine);
    }
  }

  essential_llama_engine * engine = nullptr;
  std::mutex mutex;
};

std::mutex g_requests_mutex;
std::unordered_map<std::string, request_state> g_requests;
std::mutex g_engine_cache_mutex;
std::unordered_map<std::string, std::shared_ptr<cached_engine>> g_engine_cache;

std::string to_std_string(JNIEnv * env, jstring value) {
  if (value == nullptr) {
    return std::string();
  }
  const char * chars = env->GetStringUTFChars(value, nullptr);
  std::string result(chars == nullptr ? "" : chars);
  if (chars != nullptr) {
    env->ReleaseStringUTFChars(value, chars);
  }
  return result;
}

jstring to_jstring(JNIEnv * env, const std::string & value) {
  return env->NewStringUTF(value.c_str());
}

void throw_runtime_exception(JNIEnv * env, const std::string & message) {
  jclass exception_class = env->FindClass("java/lang/RuntimeException");
  if (exception_class != nullptr) {
    env->ThrowNew(exception_class, message.c_str());
  }
}

essential_llama_model_options build_model_options(
    jint context_size,
    jint threads,
    jint batch_threads,
    jint gpu_layers,
    jboolean use_mmap,
    jboolean use_mlock) {
  essential_llama_model_options options{};
  options.context_size = context_size;
  options.threads = threads;
  options.batch_threads = batch_threads;
  options.gpu_layers = gpu_layers;
  options.use_mmap = use_mmap ? 1 : 0;
  options.use_mlock = use_mlock ? 1 : 0;
  return options;
}

essential_llama_generation_options build_generation_options(
    jint max_tokens,
    jint top_k,
    jfloat top_p,
    jfloat temperature,
    jint seed) {
  essential_llama_generation_options options{};
  options.max_tokens = max_tokens;
  options.top_k = top_k;
  options.top_p = top_p;
  options.temperature = temperature;
  options.seed = static_cast<uint32_t>(seed);
  return options;
}

void register_engine(const std::string & request_id, essential_llama_engine * engine) {
  std::lock_guard<std::mutex> lock(g_requests_mutex);
  g_requests[request_id] = request_state{engine};
}

void unregister_engine(const std::string & request_id) {
  std::lock_guard<std::mutex> lock(g_requests_mutex);
  g_requests.erase(request_id);
}

essential_llama_engine * lookup_engine(const std::string & request_id) {
  std::lock_guard<std::mutex> lock(g_requests_mutex);
  const auto iterator = g_requests.find(request_id);
  if (iterator == g_requests.end()) {
    return nullptr;
  }
  return iterator->second.engine;
}

struct stream_callback_context {
  JavaVM * vm = nullptr;
  jobject callback = nullptr;
  jmethodID on_token = nullptr;
};

void stream_token_callback(const char * token, void * user_data) {
  if (token == nullptr || user_data == nullptr) {
    return;
  }
  auto * context = static_cast<stream_callback_context *>(user_data);
  JNIEnv * env = nullptr;
  bool did_attach = false;
  if (context->vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) {
    if (context->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
      return;
    }
    did_attach = true;
  }
  jstring token_value = env->NewStringUTF(token);
  env->CallVoidMethod(context->callback, context->on_token, token_value);
  env->DeleteLocalRef(token_value);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  if (did_attach) {
    context->vm->DetachCurrentThread();
  }
}

essential_llama_engine * create_engine_or_throw(
    JNIEnv * env,
    const std::string & model_path,
    const essential_llama_model_options & model_options) {
  essential_llama_engine * engine =
      essential_llama_engine_create(model_path.c_str(), &model_options);
  if (engine == nullptr) {
    throw_runtime_exception(env, essential_llama_last_error_message());
    return nullptr;
  }
  return engine;
}

std::string engine_cache_key(
    const std::string & model_path,
    const essential_llama_model_options & model_options) {
  return model_path + "|" +
      std::to_string(model_options.context_size) + "|" +
      std::to_string(model_options.threads) + "|" +
      std::to_string(model_options.batch_threads) + "|" +
      std::to_string(model_options.gpu_layers) + "|" +
      std::to_string(model_options.use_mmap) + "|" +
      std::to_string(model_options.use_mlock);
}

std::shared_ptr<cached_engine> get_cached_engine_or_throw(
    JNIEnv * env,
    const std::string & model_path,
    const essential_llama_model_options & model_options) {
  const std::string key = engine_cache_key(model_path, model_options);
  {
    std::lock_guard<std::mutex> lock(g_engine_cache_mutex);
    const auto iterator = g_engine_cache.find(key);
    if (iterator != g_engine_cache.end()) {
      return iterator->second;
    }
  }

  essential_llama_engine * raw_engine =
      create_engine_or_throw(env, model_path, model_options);
  if (raw_engine == nullptr) {
    return nullptr;
  }
  auto engine = std::make_shared<cached_engine>(raw_engine);
  std::lock_guard<std::mutex> lock(g_engine_cache_mutex);
  const auto [iterator, inserted] = g_engine_cache.emplace(key, engine);
  if (!inserted) {
    essential_llama_engine_destroy(raw_engine);
    return iterator->second;
  }
  return engine;
}

std::string generate_or_throw(
    JNIEnv * env,
    const std::string & request_id,
    const std::string & session_id,
    essential_llama_engine * engine,
    const std::string & prompt,
    const essential_llama_generation_options & generation_options,
    essential_llama_token_callback callback,
    void * user_data) {
  register_engine(request_id, engine);
  char * output = nullptr;
  const int32_t status = essential_llama_engine_generate(
      engine,
      session_id.c_str(),
      prompt.c_str(),
      &generation_options,
      callback,
      user_data,
      &output);
  unregister_engine(request_id);
  if (status == 2) {
    throw_runtime_exception(env, "SESSION_CANCELLED: generation cancelled.");
    return std::string();
  }
  if (status != 0) {
    throw_runtime_exception(env, essential_llama_last_error_message());
    return std::string();
  }
  std::string result = output == nullptr ? "" : output;
  if (output != nullptr) {
    essential_llama_string_free(output);
  }
  return result;
}

std::string generate_cached_or_throw(
    JNIEnv * env,
    const std::string & request_id,
    const std::string & session_id,
    const std::shared_ptr<cached_engine> & cached,
    const std::string & prompt,
    const essential_llama_generation_options & generation_options,
    essential_llama_token_callback callback,
    void * user_data) {
  if (cached == nullptr || cached->engine == nullptr) {
    throw_runtime_exception(env, "Engine is not initialized.");
    return std::string();
  }
  std::lock_guard<std::mutex> lock(cached->mutex);
  return generate_or_throw(
      env,
      request_id,
      session_id,
      cached->engine,
      prompt,
      generation_options,
      callback,
      user_data);
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeRunInference(
    JNIEnv * env,
    jobject,
    jstring request_id,
    jstring model_path,
    jstring prompt,
    jint context_size,
    jint threads,
    jint batch_threads,
    jint gpu_layers,
    jboolean use_mmap,
    jboolean use_mlock,
    jint max_tokens,
    jint top_k,
    jfloat top_p,
    jfloat temperature,
    jint seed) {
  const std::string request_id_value = to_std_string(env, request_id);
  const std::string session_id_value = request_id_value;
  const std::string model_path_value = to_std_string(env, model_path);
  const std::string prompt_value = to_std_string(env, prompt);
  const auto model_options = build_model_options(
      context_size,
      threads,
      batch_threads,
      gpu_layers,
      use_mmap,
      use_mlock);
  const auto generation_options =
      build_generation_options(max_tokens, top_k, top_p, temperature, seed);
  auto engine = get_cached_engine_or_throw(env, model_path_value, model_options);
  if (engine == nullptr) {
    return nullptr;
  }
  const std::string result = generate_cached_or_throw(
      env,
      request_id_value,
      session_id_value,
      engine,
      prompt_value,
      generation_options,
      nullptr,
      nullptr);
  if (env->ExceptionCheck()) {
    return nullptr;
  }
  return to_jstring(env, result);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeStreamInference(
    JNIEnv * env,
    jobject,
    jstring request_id,
    jstring model_path,
    jstring prompt,
    jint context_size,
    jint threads,
    jint batch_threads,
    jint gpu_layers,
    jboolean use_mmap,
    jboolean use_mlock,
    jint max_tokens,
    jint top_k,
    jfloat top_p,
    jfloat temperature,
    jint seed,
    jobject callback) {
  const std::string request_id_value = to_std_string(env, request_id);
  const std::string session_id_value = request_id_value;
  const std::string model_path_value = to_std_string(env, model_path);
  const std::string prompt_value = to_std_string(env, prompt);
  const auto model_options = build_model_options(
      context_size,
      threads,
      batch_threads,
      gpu_layers,
      use_mmap,
      use_mlock);
  const auto generation_options =
      build_generation_options(max_tokens, top_k, top_p, temperature, seed);
  auto engine = get_cached_engine_or_throw(env, model_path_value, model_options);
  if (engine == nullptr) {
    return nullptr;
  }

  JavaVM * vm = nullptr;
  env->GetJavaVM(&vm);
  jclass callback_class = env->GetObjectClass(callback);
  jmethodID on_token = env->GetMethodID(callback_class, "onToken", "(Ljava/lang/String;)V");
  jobject global_callback = env->NewGlobalRef(callback);
  stream_callback_context context{
      vm,
      global_callback,
      on_token,
  };
  const std::string result = generate_cached_or_throw(
      env,
      request_id_value,
      session_id_value,
      engine,
      prompt_value,
      generation_options,
      stream_token_callback,
      &context);
  env->DeleteGlobalRef(global_callback);
  if (env->ExceptionCheck()) {
    return nullptr;
  }
  return to_jstring(env, result);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeCancel(
    JNIEnv * env,
    jobject,
    jstring request_id) {
  const std::string request_id_value = to_std_string(env, request_id);
  essential_llama_engine * engine = lookup_engine(request_id_value);
  if (engine == nullptr) {
    return JNI_FALSE;
  }
  const int32_t status = essential_llama_engine_cancel(engine);
  return status == 0 ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeAttachAdapter(
    JNIEnv * env,
    jobject,
    jstring request_id,
    jstring adapter_path,
    jfloat scale) {
  const std::string request_id_value = to_std_string(env, request_id);
  const std::string adapter_path_value = to_std_string(env, adapter_path);
  essential_llama_engine * engine = lookup_engine(request_id_value);
  if (engine == nullptr) {
    return JNI_FALSE;
  }
  essential_llama_session_attachment_options options{};
  options.scale = scale;
  const int32_t status = essential_llama_engine_attach_adapter(
      engine,
      request_id_value.c_str(),
      adapter_path_value.c_str(),
      &options);
  if (status != 0) {
    throw_runtime_exception(env, essential_llama_last_error_message());
    return JNI_FALSE;
  }
  return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeDetachAdapter(
    JNIEnv * env,
    jobject,
    jstring request_id) {
  const std::string request_id_value = to_std_string(env, request_id);
  essential_llama_engine * engine = lookup_engine(request_id_value);
  if (engine == nullptr) {
    return JNI_FALSE;
  }
  const int32_t status = essential_llama_engine_detach_adapter(
      engine,
      request_id_value.c_str());
  if (status != 0) {
    throw_runtime_exception(env, essential_llama_last_error_message());
    return JNI_FALSE;
  }
  return JNI_TRUE;
}

extern "C" JNIEXPORT jshortArray JNICALL
Java_com_example_essential_1flutter_service_EssentialNativeBridge_nativeSynthesizeTtsPcm16(
    JNIEnv * env,
    jobject,
    jstring model_path,
    jstring text,
    jfloat speed,
    jfloat pitch) {
  const std::string model_path_value = to_std_string(env, model_path);
  const std::string text_value = to_std_string(env, text);
  if (text_value.empty()) {
    return env->NewShortArray(0);
  }

  EssentialAudioContextHandle context = essential_audio_create_context();
  EssentialTtsConfig config{};
  config.voice_id = const_cast<char *>("essential-live");
  config.speed = speed;
  config.pitch = pitch;
  config.sample_rate = 22050;

  EssentialAudioSessionHandle session = essential_audio_create_tts_session(
      context,
      model_path_value.empty() ? "melotts-native-fallback" : model_path_value.c_str(),
      &config);
  if (session == nullptr) {
    if (context != nullptr) {
      essential_audio_destroy_context(context);
    }
    throw_runtime_exception(env, essential_audio_get_last_error());
    return nullptr;
  }

  EssentialAudioBuffer * output = nullptr;
  const int status = essential_audio_tts_synthesize(session, text_value.c_str(), &output);
  if (status != 0 || output == nullptr || output->samples == nullptr || output->num_samples <= 0) {
    essential_audio_destroy_session(session);
    if (context != nullptr) {
      essential_audio_destroy_context(context);
    }
    throw_runtime_exception(env, essential_audio_get_last_error());
    return nullptr;
  }

  jshortArray array = env->NewShortArray(output->num_samples);
  if (array != nullptr) {
    std::vector<jshort> pcm(static_cast<size_t>(output->num_samples));
    for (int i = 0; i < output->num_samples; ++i) {
      const float sample = std::max(-1.0f, std::min(1.0f, output->samples[i]));
      pcm[static_cast<size_t>(i)] = static_cast<jshort>(sample * 32767.0f);
    }
    env->SetShortArrayRegion(array, 0, output->num_samples, pcm.data());
  }

  essential_audio_free_buffer(output);
  essential_audio_destroy_session(session);
  if (context != nullptr) {
    essential_audio_destroy_context(context);
  }
  return array;
}
