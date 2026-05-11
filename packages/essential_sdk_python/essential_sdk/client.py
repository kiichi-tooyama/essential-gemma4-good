from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


class EssentialError(RuntimeError):
    pass


@dataclass(frozen=True)
class EssentialModel:
    model_id: str
    path: Path
    family: str = "llama.cpp"
    capabilities: tuple[str, ...] = ("text_generation",)

    @property
    def is_installed(self) -> bool:
        return self.path.exists()


@dataclass(frozen=True)
class GenerateResult:
    request_id: str
    text: str
    model_id: str


class EssentialClient:
    """Small Python SDK facade for local Essential runtimes.

    This package intentionally keeps runtime binding pluggable. The default
    runtime returns deterministic local responses so application integrations can
    be tested without native libraries; production callers can inject a runtime
    with generate(), stream(), attach_adapter(), and detach_adapter() methods.
    """

    def __init__(self, models: Iterable[EssentialModel], runtime=None):
        self._models = list(models)
        self._runtime = runtime or _EchoRuntime()
        self._loaded_model: EssentialModel | None = None
        self._next_request = 1

    def list_models(self) -> list[EssentialModel]:
        return [model for model in self._models if model.is_installed]

    def generate(
        self,
        prompt: str,
        *,
        model_id: str | None = None,
        max_tokens: int = 64,
    ) -> GenerateResult:
        model = self._resolve_model(model_id)
        self._ensure_loaded(model)
        request_id = self._new_request_id()
        text = self._runtime.generate(prompt, max_tokens=max_tokens)
        return GenerateResult(request_id=request_id, text=text, model_id=model.model_id)

    def stream(
        self,
        prompt: str,
        *,
        model_id: str | None = None,
        max_tokens: int = 64,
    ) -> Iterator[str]:
        model = self._resolve_model(model_id)
        self._ensure_loaded(model)
        yield from self._runtime.stream(prompt, max_tokens=max_tokens)

    def attach_adapter(self, session_id: str, adapter_path: str | Path) -> None:
        self._runtime.attach_adapter(session_id, Path(adapter_path))

    def detach_adapter(self, session_id: str) -> None:
        self._runtime.detach_adapter(session_id)

    def _resolve_model(self, model_id: str | None) -> EssentialModel:
        models = self.list_models()
        if not models:
            raise EssentialError("No installed Essential model was found.")
        if model_id is None:
            return models[0]
        for model in models:
            if model.model_id == model_id:
                return model
        raise EssentialError(f"Model is not installed: {model_id}")

    def _ensure_loaded(self, model: EssentialModel) -> None:
        if self._loaded_model == model:
            return
        self._runtime.load_model(model.path)
        self._loaded_model = model

    def _new_request_id(self) -> str:
        request_id = f"py-{self._next_request}"
        self._next_request += 1
        return request_id


class _EchoRuntime:
    def load_model(self, model_path: Path) -> None:
        if not model_path.exists():
            raise EssentialError(f"Model path not found: {model_path}")

    def generate(self, prompt: str, *, max_tokens: int) -> str:
        words = prompt.strip().split()
        return " ".join(words[:max_tokens]) if words else ""

    def stream(self, prompt: str, *, max_tokens: int) -> Iterator[str]:
        text = self.generate(prompt, max_tokens=max_tokens)
        for token in text.split():
            yield token + " "

    def attach_adapter(self, session_id: str, adapter_path: Path) -> None:
        if not adapter_path.exists():
            raise EssentialError(f"Adapter path not found: {adapter_path}")

    def detach_adapter(self, session_id: str) -> None:
        return None
