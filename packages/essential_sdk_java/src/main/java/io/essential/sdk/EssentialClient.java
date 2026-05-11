package io.essential.sdk;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.stream.Stream;

public final class EssentialClient {
    private final List<EssentialModel> models;
    private final EssentialRuntime runtime;
    private EssentialModel loadedModel;
    private int nextRequestId = 1;

    public EssentialClient(List<EssentialModel> models) {
        this(models, new EchoRuntime());
    }

    public EssentialClient(List<EssentialModel> models, EssentialRuntime runtime) {
        this.models = List.copyOf(models);
        this.runtime = Objects.requireNonNull(runtime);
    }

    public List<EssentialModel> listModels() {
        return models.stream().filter(EssentialModel::isInstalled).toList();
    }

    public GenerateResult generate(String prompt, String modelId, int maxTokens) {
        EssentialModel model = resolveModel(modelId);
        ensureLoaded(model);
        String text = runtime.generate(prompt, maxTokens);
        return new GenerateResult("java-" + nextRequestId++, text, model.modelId());
    }

    public Stream<String> stream(String prompt, String modelId, int maxTokens) {
        EssentialModel model = resolveModel(modelId);
        ensureLoaded(model);
        return runtime.stream(prompt, maxTokens);
    }

    public void attachAdapter(String sessionId, Path adapterPath) {
        runtime.attachAdapter(sessionId, adapterPath);
    }

    public void detachAdapter(String sessionId) {
        runtime.detachAdapter(sessionId);
    }

    private EssentialModel resolveModel(String modelId) {
        List<EssentialModel> installed = listModels();
        if (installed.isEmpty()) {
            throw new IllegalStateException("No installed Essential model was found.");
        }
        if (modelId == null || modelId.isBlank()) {
            return installed.get(0);
        }
        return installed.stream()
            .filter(model -> model.modelId().equals(modelId))
            .findFirst()
            .orElseThrow(() -> new IllegalStateException("Model is not installed: " + modelId));
    }

    private void ensureLoaded(EssentialModel model) {
        if (model.equals(loadedModel)) {
            return;
        }
        runtime.loadModel(model.path());
        loadedModel = model;
    }

    private static final class EchoRuntime implements EssentialRuntime {
        @Override
        public void loadModel(Path modelPath) {
            if (!Files.exists(modelPath)) {
                throw new IllegalStateException("Model path not found: " + modelPath);
            }
        }

        @Override
        public String generate(String prompt, int maxTokens) {
            String[] words = prompt == null ? new String[0] : prompt.trim().split("\\s+");
            List<String> selected = new ArrayList<>();
            for (int i = 0; i < words.length && i < maxTokens; i++) {
                if (!words[i].isBlank()) {
                    selected.add(words[i]);
                }
            }
            return String.join(" ", selected);
        }

        @Override
        public Stream<String> stream(String prompt, int maxTokens) {
            return Stream.of(generate(prompt, maxTokens).split("\\s+"))
                .filter(token -> !token.isBlank())
                .map(token -> token + " ");
        }

        @Override
        public void attachAdapter(String sessionId, Path adapterPath) {
            if (!Files.exists(adapterPath)) {
                throw new IllegalStateException("Adapter path not found: " + adapterPath);
            }
        }

        @Override
        public void detachAdapter(String sessionId) {
        }
    }
}
