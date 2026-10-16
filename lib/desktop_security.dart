/// Fail closed if a build points authentication and sync at different services,
/// or would transmit company credentials without TLS.
void validateServerConfiguration(String authUrl, String syncUrl) {
  final auth = Uri.tryParse(authUrl);
  final sync = Uri.tryParse(syncUrl);
  for (final endpoint in [auth, sync]) {
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw StateError('Saleo requires a valid HTTPS server configuration.');
    }
  }
  if (authUrl.replaceAll(RegExp(r'/+$'), '') !=
      syncUrl.replaceAll(RegExp(r'/+$'), '')) {
    throw StateError(
      'Authentication and synchronization must use the same company server.',
    );
  }
}
