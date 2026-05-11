# Essential Java SDK

Lightweight Java facade for Essential local runtimes.

```java
EssentialModel model = new EssentialModel(
    "mini",
    Path.of("/models/mini.gguf"),
    "llama.cpp",
    List.of("text_generation")
);
EssentialClient client = new EssentialClient(List.of(model));
GenerateResult result = client.generate("hello from essential", "mini", 64);
```
