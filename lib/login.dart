import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:nscgschedule/requests.dart';
import 'package:nscgschedule/settings.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final CookieManager _cookieManager = CookieManager.instance();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Login'),
      ),
      body: Center(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('https://my.nulc.ac.uk')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            useOnLoadResource: true,
            allowsBackForwardNavigationGestures: true,
            thirdPartyCookiesEnabled: true,
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserGesture: false,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            cacheEnabled: true,
            clearCache: false,
            useShouldOverrideUrlLoading: false,
          ),
          onReceivedServerTrustAuthRequest: (controller, challenge) async {
            final host = challenge.protectionSpace.host;
            debugPrint('SSL trust challenge host: $host');

            final allowed = host == 'nulc.ac.uk' || host.endsWith('.nulc.ac.uk');

            return ServerTrustAuthResponse(
              action: allowed
                  ? ServerTrustAuthResponseAction.PROCEED
                  : ServerTrustAuthResponseAction.CANCEL,
            );
          },
          onLoadStop: (controller, url) async {
            if (!url.toString().contains('authToken') &&
                url.toString().startsWith('https://my.nulc.ac.uk')) {
              try {
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      // Close any open dialogs first
                      if (Navigator.canPop(context)) {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                      // Show error dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cannot Login'),
                          content: const Text(
                            'This error is commonly caused by being connected to college wifi which prevents this page from redirecting to the login screen.\n\nPlease try again using mobile data or a different network.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  });
                }
              } catch (e) {
                debugPrint('Error showing login error dialog: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Unable to authenticate. Please check your connection.',
                      ),
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              }
              return; // Stop further execution on auth error
            }

            if (url.toString().startsWith('https://my.nulc.ac.uk')) {
              try {
                // Save cookies first
                final cookies = await _cookieManager.getCookies(
                  url: WebUri('https://my.nulc.ac.uk'),
                );
                await settings.setKey('cookies', cookies.toString());
                await settings.setBool('loggedin', true);

                // Get timetable
                await NSCGRequests().getTimeTable();

                // Clean up after navigation is scheduled
                await _cookieManager.deleteAllCookies();

                // ignore: use_build_context_synchronously
                context.go('/Timetable');
              } catch (e) {
                debugPrint('Login error: $e');
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error during login. Please try again.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            }
          },
        ),
      ),
    );
  }
}
