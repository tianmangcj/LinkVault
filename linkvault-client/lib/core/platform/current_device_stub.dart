class CurrentDevice {
  const CurrentDevice._();

  static String get name => 'Web Browser';

  static Future<String> resolveName() async => name;

  static String get platform => 'web';
}
