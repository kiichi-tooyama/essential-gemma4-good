#include "adapter_manifest.h"

#include <algorithm>

namespace essential {

namespace {

bool matches_or_empty(
    const std::vector<std::string> & values,
    const std::string & candidate) {
  if (values.empty()) {
    return true;
  }
  return std::find(values.begin(), values.end(), candidate) != values.end();
}

}  // namespace

bool adapter_manifest_is_compatible(
    const adapter_manifest & manifest,
    const std::string & base_model_id,
    const std::string & variant_id,
    const std::string & quantization,
    const std::string & runtime) {
  return std::any_of(
      manifest.compatibility_matrix.begin(),
      manifest.compatibility_matrix.end(),
      [&](const adapter_compatibility_entry & entry) {
        return entry.base_model_id == base_model_id &&
            matches_or_empty(entry.variant_ids, variant_id) &&
            matches_or_empty(entry.quantizations, quantization) &&
            matches_or_empty(entry.runtimes, runtime);
      });
}

}  // namespace essential