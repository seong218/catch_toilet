class AppConfig {
  static const appName = 'Catchy Toilet';
  static const appVersion = '1.0.0';

  static const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
