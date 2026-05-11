package io.essential.sdk;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public record EssentialModel(
    String modelId,
    Path path,
    String family,
    List<String> capabilities
) {
    public boolean isInstalled() {
        return Files.exists(path);
    }
}
