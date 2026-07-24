/// Lightweight holder for the current auth token, kept OUTSIDE the Riverpod
/// provider graph on purpose.
///
/// Why: apiClientProvider -> authServiceProvider -> authNotifierProvider is
/// a chain. If the Dio interceptor inside apiClientProvider reads
/// authNotifierProvider to get the token, that closes the loop
/// (apiClientProvider -> ... -> authNotifierProvider -> ... -> apiClientProvider)
/// and Riverpod throws CircularDependencyError the moment a request fires.
///
/// AuthNotifier keeps this in sync (see auth_provider.dart), and the Dio
/// interceptor reads/writes it directly, with no ref involved.
class AuthSession {
  static String? token;
  static void Function()? onUnauthorized;
}
