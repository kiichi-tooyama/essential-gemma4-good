#ifndef ESSENTIAL_ADAPTER_MANIFEST_H
#define ESSENTIAL_ADAPTER_MANIFEST_H

#include <string>
#include <vector>

namespace essential {

struct adapter_weight_descriptor {
  std::string file_name;
  std::string relative_path;
  std::string sha256;
  int64_t size_bytes = 0;
  std::string format;
};

struct adapter_signature_descriptor {
  std::string algorithm;
  std::string key_id;
  std::string value;
  std::string public_key_path;
};

struct adapter_task_profile {
  std::string task_type;
  std::string locale;
  std::string style;
  std::string domain;
};

struct adapter_compatibility_entry {
  std::string base_model_id;
  std::vector<std::string> variant_ids;
  std::vector<std::string> quantizations;
  std::vector<std::string> runtimes;
};

struct adapter_manifest {
  std::string manifest_type;
  std::string adapter_id;
  std::string owner_app_id;
  std::string display_name;
  std::string version;
  std::string runtime;
  std::string base_model_id;
  std::string namespace_id;
  adapter_weight_descriptor weights;
  adapter_signature_descriptor signature;
  adapter_task_profile task_profile;
  std::vector<adapter_compatibility_entry> compatibility_matrix;
};

bool adapter_manifest_is_compatible(
    const adapter_manifest & manifest,
    const std::string & base_model_id,
    const std::string & variant_id,
    const std::string & quantization,
    const std::string & runtime);

}  // namespace essential

#endif