package io.essential.sdk;

import java.nio.file.Path;
import java.util.stream.Stream;

public interface EssentialRuntime {
    void loadModel(Path modelPath);

    String generate(String prompt, int maxTokens);

    Stream<String> stream(String prompt, int maxTokens);

    void attachAdapter(String sessionId, Path adapterPath);

    void detachAdapter(String sessionId);
}
