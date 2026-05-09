#include "essential_llama.h"

#include "llama.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <unordered_map>
#include <mutex>
#include <string>
#include <vector>

#if defined(__ANDROID__) && defined(ESSENTIAL_LLAMA_PERF_LOGS)
#include <android/log.h>
#endif

struct essential_llama_session_state {
  llama_context * ctx = nullptr;
  int32_t context_size = 0;
  std::vector<llama_token> tokens;

  ~essential_llama_session_state() {
    if (ctx != nullptr) {
      llama_free(ctx);
    }
  }
};

struct essential_llama_engine {
  llama_model * model;
  essential_llama_model_options options;
  std::atomic<bool> cancel_requested;
  std::mutex mutex;
  std::unordered_map<std::string, std::shared_ptr<llama_adapter_lora>> adapters_by_path;
  std::unordered_map<std::string, std::string> adapter_path_by_session;
  std::unordered_map<std::string, float> adapter_scale_by_session;
  std::unordered_map<std::string, std::unique_ptr<essential_llama_session_state>> sessions_by_id;
};

namespace {

thread_local std::string g_last_error;
std::once_flag g_backend_once;

void log_perf(const std::string & message) {
#if defined(__ANDROID__) && defined(ESSENTIAL_LLAMA_PERF_LOGS)
  __android_log_print(ANDROID_LOG_INFO, "EssentialLlama", "%s", message.c_str());
#else
  (void)message;
#endif
}

void set_last_error(const std::string & message) {
  g_last_error = message;
}

const essential_llama_model_options & default_model_options() {
  static const essential_llama_model_options options = {
      2048,
      4,
      4,
      0,
      1,
      0,
  };
  return options;
}

const essential_llama_generation_options & default_generation_options() {
  static const essential_llama_generation_options options = {
      128,
      40,
      0.95f,
      0.8f,
      42,
  };
  return options;
}

const essential_llama_session_attachment_options & default_attachment_options() {
  static const essential_llama_session_attachment_options options = {
      1.0f,
  };
  return options;
}

bool abort_generation(void * data) {
  auto * engine = static_cast<essential_llama_engine *>(data);
  return engine != nullptr && engine->cancel_requested.load();
}

std::string token_to_piece(const llama_vocab * vocab, llama_token token) {
  std::vector<char> buffer(128);
  int piece_length =
      llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, true);
  if (piece_length < 0) {
    buffer.resize(static_cast<size_t>(-piece_length));
    piece_length = llama_token_to_piece(
        vocab,
        token,
        buffer.data(),
        buffer.size(),
        0,
        true);
  }
  if (piece_length < 0) {
    return std::string();
  }
  return std::string(buffer.data(), static_cast<size_t>(piece_length));
}

bool is_continuation_byte(unsigned char value) {
  return (value & 0xC0) == 0x80;
}

std::string sanitize_utf8(const std::string & input) {
  std::string output;
  output.reserve(input.size());
  for (size_t i = 0; i < input.size();) {
    const auto first = static_cast<unsigned char>(input[i]);
    if (first <= 0x7F) {
      output.push_back(input[i++]);
      continue;
    }

    size_t length = 0;
    if (first >= 0xC2 && first <= 0xDF) {
      length = 2;
    } else if (first >= 0xE0 && first <= 0xEF) {
      length = 3;
    } else if (first >= 0xF0 && first <= 0xF4) {
      length = 4;
    } else {
      ++i;
      continue;
    }

    if (i + length > input.size()) {
      break;
    }
    bool valid = true;
    for (size_t j = 1; j < length; ++j) {
      if (!is_continuation_byte(static_cast<unsigned char>(input[i + j]))) {
        valid = false;
        break;
      }
    }
    if (!valid) {
      ++i;
      continue;
    }
    output.append(input, i, length);
    i += length;
  }
  return output;
}

llama_sampler * create_sampler(
    const essential_llama_generation_options & options) {
  auto sampler_params = llama_sampler_chain_default_params();
  sampler_params.no_perf = true;
  llama_sampler * sampler = llama_sampler_chain_init(sampler_params);
  if (options.temperature <= 0.0f) {
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    return sampler;
  }
  if (options.top_k > 0) {
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(options.top_k));
  }
  if (options.top_p > 0.0f && options.top_p <= 1.0f) {
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(options.top_p, 1));
  }
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(96, 1.18f, 0.08f, 0.03f));
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(options.temperature));
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(options.seed));
  return sampler;
}

bool build_prompt_tokens(
    const llama_vocab * vocab,
    const std::string & prompt,
    std::vector<llama_token> * tokens_out) {
  const int token_count = -llama_tokenize(
      vocab,
      prompt.c_str(),
      static_cast<int32_t>(prompt.size()),
      nullptr,
      0,
      true,
      true);
  if (token_count <= 0) {
    set_last_error("Prompt tokenization failed.");
    return false;
  }
  tokens_out->resize(static_cast<size_t>(token_count));
  const int written = llama_tokenize(
      vocab,
      prompt.c_str(),
      static_cast<int32_t>(prompt.size()),
      tokens_out->data(),
      token_count,
      true,
      true);
  if (written < 0) {
    set_last_error("Prompt tokenization write failed.");
    return false;
  }
  return true;
}

size_t common_prefix_size(
    const std::vector<llama_token> & left,
    const std::vector<llama_token> & right) {
  const size_t limit = std::min(left.size(), right.size());
  size_t index = 0;
  while (index < limit && left[index] == right[index]) {
    ++index;
  }
  return index;
}

llama_context * create_context(
    essential_llama_engine * engine,
    int32_t requested_context) {
  auto ctx_params = llama_context_default_params();
  ctx_params.n_ctx = requested_context;
  ctx_params.n_batch = std::max(1, requested_context);
  ctx_params.no_perf = true;
  llama_context * ctx = llama_init_from_model(engine->model, ctx_params);
  if (ctx == nullptr) {
    set_last_error("Failed to create inference context.");
    return nullptr;
  }
  llama_set_n_threads(
      ctx,
      std::max(1, engine->options.threads),
      std::max(1, engine->options.batch_threads));
  llama_set_abort_callback(ctx, abort_generation, engine);
  return ctx;
}

essential_llama_session_state * session_state_for(
    essential_llama_engine * engine,
    const std::string & session_id) {
  auto it = engine->sessions_by_id.find(session_id);
  if (it != engine->sessions_by_id.end()) {
    return it->second.get();
  }
  auto state = std::make_unique<essential_llama_session_state>();
  auto * raw = state.get();
  engine->sessions_by_id.emplace(session_id, std::move(state));
  return raw;
}

std::shared_ptr<llama_adapter_lora> retain_or_load_adapter(
    essential_llama_engine * engine,
    const std::string & adapter_path) {
  auto existing = engine->adapters_by_path.find(adapter_path);
  if (existing != engine->adapters_by_path.end()) {
    return existing->second;
  }
  llama_adapter_lora * raw_adapter =
      llama_adapter_lora_init(engine->model, adapter_path.c_str());
  if (raw_adapter == nullptr) {
    set_last_error("Failed to load LoRA adapter.");
    return nullptr;
  }
  auto shared_adapter = std::shared_ptr<llama_adapter_lora>(
      raw_adapter,
      [](llama_adapter_lora * adapter) { llama_adapter_lora_free(adapter); });
  engine->adapters_by_path.emplace(adapter_path, shared_adapter);
  return shared_adapter;
}

bool apply_session_adapter(
    essential_llama_engine * engine,
    const std::string & session_id,
    llama_context * ctx) {
  if (session_id.empty()) {
    return true;
  }

  std::shared_ptr<llama_adapter_lora> adapter;
  float scale = 1.0f;
  const auto path_it = engine->adapter_path_by_session.find(session_id);
  if (path_it == engine->adapter_path_by_session.end()) {
    return true;
  }
  const auto adapter_it = engine->adapters_by_path.find(path_it->second);
  if (adapter_it == engine->adapters_by_path.end()) {
    set_last_error("Adapter session binding is missing from cache.");
    return false;
  }
  adapter = adapter_it->second;
  const auto scale_it = engine->adapter_scale_by_session.find(session_id);
  if (scale_it != engine->adapter_scale_by_session.end()) {
    scale = scale_it->second;
  }

  llama_adapter_lora * raw_adapter = adapter.get();
  float scales[1] = {scale};
  llama_adapter_lora * adapters[1] = {raw_adapter};
  if (llama_set_adapters_lora(ctx, adapters, 1, scales) != 0) {
    set_last_error("Failed to apply LoRA adapter to the session context.");
    return false;
  }
  return true;
}

}  // namespace

essential_llama_engine * essential_llama_engine_create(
    const char * model_path,
    const essential_llama_model_options * options) {
  set_last_error(std::string());
  if (model_path == nullptr || std::strlen(model_path) == 0) {
    set_last_error("Model path is empty.");
    return nullptr;
  }
  std::call_once(g_backend_once, []() { llama_backend_init(); });
  const auto resolved_options =
      options != nullptr ? *options : default_model_options();
  auto model_params = llama_model_default_params();
  model_params.n_gpu_layers = resolved_options.gpu_layers;
  model_params.use_mmap = resolved_options.use_mmap != 0;
  model_params.use_mlock = resolved_options.use_mlock != 0;
  llama_model * model = llama_model_load_from_file(model_path, model_params);
  if (model == nullptr) {
    set_last_error("Failed to load GGUF model.");
    return nullptr;
  }
  auto * engine = new essential_llama_engine{
      model,
      resolved_options,
      false,
      std::mutex(),
      {},
      {},
      {},
      {},
  };
  return engine;
}

void essential_llama_engine_destroy(essential_llama_engine * engine) {
  if (engine == nullptr) {
    return;
  }
  engine->sessions_by_id.clear();
  if (engine->model != nullptr) {
    llama_model_free(engine->model);
  }
  delete engine;
}

int32_t essential_llama_engine_generate(
    essential_llama_engine * engine,
    const char * session_id,
    const char * prompt,
    const essential_llama_generation_options * options,
    essential_llama_token_callback callback,
    void * user_data,
    char ** output_out) {
  set_last_error(std::string());
  if (engine == nullptr || engine->model == nullptr) {
    set_last_error("Engine is not initialized.");
    return 1;
  }
  if (prompt == nullptr) {
    set_last_error("Prompt is null.");
    return 1;
  }
  if (output_out == nullptr) {
    set_last_error("Output pointer is null.");
    return 1;
  }

  engine->cancel_requested.store(false);
  *output_out = nullptr;

  const auto generation_options =
      options != nullptr ? *options : default_generation_options();
  const llama_vocab * vocab = llama_model_get_vocab(engine->model);
  std::vector<llama_token> prompt_tokens;
  if (!build_prompt_tokens(vocab, prompt, &prompt_tokens)) {
    return 1;
  }
  log_perf(
      "generate_start prompt_tokens=" + std::to_string(prompt_tokens.size()) +
      " max_tokens=" + std::to_string(generation_options.max_tokens));

  const int requested_context = std::max(
      engine->options.context_size,
      static_cast<int32_t>(prompt_tokens.size()) + generation_options.max_tokens + 8);
  const int trained_context = llama_model_n_ctx_train(engine->model);
  if (requested_context > trained_context && trained_context > 0) {
    set_last_error("Requested context exceeds model context window.");
    return 1;
  }

  const std::string resolved_session_id =
      session_id != nullptr && std::strlen(session_id) > 0
          ? std::string(session_id)
          : std::string("__default__");

  std::unique_lock<std::mutex> lock(engine->mutex);
  essential_llama_session_state * state =
      session_state_for(engine, resolved_session_id);
  if (state == nullptr) {
    set_last_error("Failed to allocate llama session state.");
    return 1;
  }

  const bool needs_new_context =
      state->ctx == nullptr || state->context_size < requested_context;
  if (needs_new_context) {
    state->tokens.clear();
    if (state->ctx != nullptr) {
      llama_free(state->ctx);
      state->ctx = nullptr;
    }
    state->ctx = create_context(engine, requested_context);
    state->context_size = requested_context;
    if (state->ctx == nullptr) {
      return 1;
    }
  }

  llama_context * ctx = state->ctx;
  log_perf(
      "context_ready n_ctx=" + std::to_string(state->context_size) +
      " cached_tokens=" + std::to_string(state->tokens.size()) +
      " threads=" + std::to_string(engine->options.threads));

  if (!apply_session_adapter(engine, resolved_session_id, ctx)) {
    return 1;
  }

  size_t prefix_size = common_prefix_size(state->tokens, prompt_tokens);
  if (prefix_size < state->tokens.size()) {
    if (!llama_memory_seq_rm(
            llama_get_memory(ctx),
            0,
            static_cast<llama_pos>(prefix_size),
            -1)) {
      llama_memory_clear(llama_get_memory(ctx), true);
      prefix_size = 0;
    }
    state->tokens.resize(prefix_size);
  }
  if (prefix_size == 0 && !state->tokens.empty()) {
    llama_memory_clear(llama_get_memory(ctx), true);
    state->tokens.clear();
  }

  llama_sampler * sampler = create_sampler(generation_options);

  if (llama_model_has_encoder(engine->model)) {
    llama_batch batch =
        llama_batch_get_one(prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));
    if (llama_encode(ctx, batch) != 0) {
      llama_sampler_free(sampler);
      set_last_error("Prompt encoding failed.");
      return 1;
    }
    llama_token decoder_start_token = llama_model_decoder_start_token(engine->model);
    if (decoder_start_token == LLAMA_TOKEN_NULL) {
      decoder_start_token = llama_vocab_bos(vocab);
    }
    batch = llama_batch_get_one(&decoder_start_token, 1);
    log_perf(
        "decode_start position=0"
        " batch_tokens=" + std::to_string(batch.n_tokens));
    const int decode_status = llama_decode(ctx, batch);
    log_perf(
        "decode_end position=0"
        " status=" + std::to_string(decode_status));
    if (decode_status != 0) {
      llama_sampler_free(sampler);
      if (engine->cancel_requested.load()) {
        set_last_error("Generation cancelled.");
        return 2;
      }
      set_last_error("llama_decode failed.");
      return 1;
    }
  } else {
    constexpr int32_t kPromptChunkSize = 512;
    int32_t prompt_position = static_cast<int32_t>(prefix_size);
    while (prompt_position < static_cast<int32_t>(prompt_tokens.size())) {
      const int32_t chunk_size = std::min(
          kPromptChunkSize,
          static_cast<int32_t>(prompt_tokens.size()) - prompt_position);
      llama_batch batch = llama_batch_get_one(
          prompt_tokens.data() + prompt_position,
          chunk_size);
      log_perf(
          "prefill_start position=" + std::to_string(prompt_position) +
          " batch_tokens=" + std::to_string(batch.n_tokens));
      const int decode_status = llama_decode(ctx, batch);
      log_perf(
          "prefill_end position=" + std::to_string(prompt_position) +
          " status=" + std::to_string(decode_status));
      if (decode_status != 0) {
        llama_sampler_free(sampler);
        if (engine->cancel_requested.load()) {
          set_last_error("Generation cancelled.");
          return 2;
        }
        set_last_error("Prompt prefill failed.");
        return 1;
      }
      prompt_position += chunk_size;
      state->tokens.insert(
          state->tokens.end(),
          prompt_tokens.begin() + prompt_position - chunk_size,
          prompt_tokens.begin() + prompt_position);
      if (engine->cancel_requested.load()) {
        llama_sampler_free(sampler);
        set_last_error("Generation cancelled.");
        return 2;
      }
    }
  }

  std::string generated_text;
  bool stop_requested = false;
  const std::vector<std::string> stop_sequences{
      "\nUser:",
      "\nAssistant:",
      "\nuser\n",
      "\nassistant\n",
      "\nmodel\n",
      "<end_of_turn>",
      "<start_of_turn>",
      "</s>",
      "<|user|>",
      "<|assistant|>",
      "<|system|>",
      "<turn|>",
      "<|turn>user",
      "<|turn>model",
      "<|turn>system",
      "<|tool_call>",
      "<tool_call|>",
      "<|tool_response>",
      "<tool_response|>",
      "<|channel>",
      "<channel|>",
      "[Start thinking]",
      "[End thinking]",
  };

  for (int32_t generated_tokens = 0;
       generated_tokens < generation_options.max_tokens && !stop_requested;
       ++generated_tokens) {
    const llama_token token = llama_sampler_sample(sampler, ctx, -1);
    if (llama_vocab_is_eog(vocab, token)) {
      break;
    }
    state->tokens.push_back(token);

    const std::string piece = token_to_piece(vocab, token);
    if (!piece.empty()) {
      generated_text.append(piece);
      for (const auto & stop_sequence : stop_sequences) {
        const auto stop_position = generated_text.find(stop_sequence);
        if (stop_position != std::string::npos) {
          generated_text.erase(stop_position);
          stop_requested = true;
          break;
        }
      }
      if (callback != nullptr) {
        const std::string safe_piece = sanitize_utf8(stop_requested ? "" : piece);
        if (!safe_piece.empty() || stop_requested) {
          callback(safe_piece.c_str(), user_data);
        }
      }
    }

    llama_token next_token = token;
    llama_batch batch = llama_batch_get_one(&next_token, 1);
    log_perf(
        "decode_start generated=" + std::to_string(generated_tokens) +
        " batch_tokens=" + std::to_string(batch.n_tokens));
    const int decode_status = llama_decode(ctx, batch);
    log_perf(
        "decode_end generated=" + std::to_string(generated_tokens) +
        " status=" + std::to_string(decode_status));
    if (decode_status != 0) {
      llama_sampler_free(sampler);
      if (engine->cancel_requested.load()) {
        set_last_error("Generation cancelled.");
        return 2;
      }
      set_last_error("llama_decode failed.");
      return 1;
    }
  }

  llama_sampler_free(sampler);

  const std::string safe_generated_text = sanitize_utf8(generated_text);
  char * owned_output =
      static_cast<char *>(std::malloc(safe_generated_text.size() + 1));
  if (owned_output == nullptr) {
    set_last_error("Failed to allocate response buffer.");
    return 1;
  }
  std::memcpy(
      owned_output,
      safe_generated_text.c_str(),
      safe_generated_text.size() + 1);
  *output_out = owned_output;
  return 0;
}

int32_t essential_llama_engine_attach_adapter(
    essential_llama_engine * engine,
    const char * session_id,
    const char * adapter_path,
    const essential_llama_session_attachment_options * options) {
  set_last_error(std::string());
  if (engine == nullptr || engine->model == nullptr) {
    set_last_error("Engine is not initialized.");
    return 1;
  }
  if (session_id == nullptr || std::strlen(session_id) == 0) {
    set_last_error("Session id is empty.");
    return 1;
  }
  if (adapter_path == nullptr || std::strlen(adapter_path) == 0) {
    set_last_error("Adapter path is empty.");
    return 1;
  }

  std::lock_guard<std::mutex> lock(engine->mutex);
  auto adapter = retain_or_load_adapter(engine, std::string(adapter_path));
  if (adapter == nullptr) {
    return 1;
  }
  const auto resolved_options =
      options != nullptr ? *options : default_attachment_options();
  engine->adapter_path_by_session[session_id] = adapter_path;
  engine->adapter_scale_by_session[session_id] = resolved_options.scale;
  return 0;
}

int32_t essential_llama_engine_detach_adapter(
    essential_llama_engine * engine,
    const char * session_id) {
  set_last_error(std::string());
  if (engine == nullptr || engine->model == nullptr) {
    set_last_error("Engine is not initialized.");
    return 1;
  }
  if (session_id == nullptr || std::strlen(session_id) == 0) {
    set_last_error("Session id is empty.");
    return 1;
  }

  std::lock_guard<std::mutex> lock(engine->mutex);
  engine->adapter_path_by_session.erase(session_id);
  engine->adapter_scale_by_session.erase(session_id);
  return 0;
}

int32_t essential_llama_engine_cancel(essential_llama_engine * engine) {
  if (engine == nullptr) {
    set_last_error("Engine is not initialized.");
    return 1;
  }
  engine->cancel_requested.store(true);
  return 0;
}

void essential_llama_string_free(char * value) {
  std::free(value);
}

const char * essential_llama_last_error_message(void) {
  return g_last_error.c_str();
}
