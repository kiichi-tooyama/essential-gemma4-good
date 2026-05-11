class AppConfig {
  AppConfig._();

  static const registryApiUrl = String.fromEnvironment(
    'ESSENTIAL_REGISTRY_URL',
    defaultValue: '',
  );

  static const huggingFaceOAuthClientId = String.fromEnvironment(
    'ESSENTIAL_HF_OAUTH_CLIENT_ID',
    defaultValue: '',
  );

  static const huggingFaceOAuthRedirectUri = String.fromEnvironment(
    'ESSENTIAL_HF_OAUTH_REDIRECT_URI',
    defaultValue: 'essential://hf-auth',
  );

  static const huggingFaceArtifactBaseUrl = String.fromEnvironment(
    'ESSENTIAL_HF_ARTIFACT_BASE_URL',
    defaultValue: '',
  );
}
