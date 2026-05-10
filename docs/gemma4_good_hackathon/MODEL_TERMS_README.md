# Model Terms README

The hackathon package may include Gemma 4 LiteRT-LM model files for demo
reproducibility. These model files are not owned or relicensed by the Essential
project.

Users must follow the applicable Google Gemma terms and any model-card
conditions. The Essential CC BY 4.0 project license does not grant extra rights
to modify, redistribute, or commercially use Gemma model files.

If the release folder includes model binaries, keep checksums and file names in
the release manifest so judges can verify exactly what was bundled.

## Hugging Face downloads

Essential can download LiteRT-LM model files from Hugging Face instead of
requiring the project to host every large binary itself. For gated repositories,
the app follows the same user flow as Google AI Edge Gallery: it checks whether
the model URL is accessible, opens a browser-based Hugging Face OAuth login when
authentication is required, retries with the returned access token, and opens the
model page if the user still needs to accept repository terms.

To enable the OAuth path, create a Hugging Face OAuth application and register
`essential://hf-auth` as a redirect URI. Build the app with:

```sh
--dart-define=ESSENTIAL_HF_OAUTH_CLIENT_ID=<client_id>
```

The redirect URI can be changed with:

```sh
--dart-define=ESSENTIAL_HF_OAUTH_REDIRECT_URI=<redirect_uri>
```

## Artifact hosting policy

Essential no longer falls back to downloading model artifacts from the project
server. Runtime catalog metadata may still describe models and expected
checksums, but the model binaries themselves must come from Hugging Face.

For upstream public artifacts, Essential uses hardcoded Hugging Face URLs. For
project-specific artifacts, upload the exact files named by the catalog manifest
to a Hugging Face repository and build with:

```sh
--dart-define=ESSENTIAL_HF_ARTIFACT_BASE_URL=https://huggingface.co/<owner>/<repo>/resolve/main/artifacts/
```

The uploaded files must keep the same filename, byte size, and SHA-256 checksum
as the manifest. If an artifact has no Hugging Face source, the app fails
explicitly instead of downloading from `models.node-cloud.net`.
