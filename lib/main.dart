import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SolaraApp());
}

class SolaraApp extends StatelessWidget {
  const SolaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solara',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'SpecialElite',
        scaffoldBackgroundColor: const Color(0xFF0A0608),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6B5F),
          secondary: Color(0xFF272B34),
        ),
        useMaterial3: true,
      ),
      home: const SolaraHomePage(),
    );
  }
}

class SolaraHomePage extends StatefulWidget {
  const SolaraHomePage({super.key});

  @override
  State<SolaraHomePage> createState() => _SolaraHomePageState();
}

class _SolaraHomePageState extends State<SolaraHomePage> {
  static const _port = 8079;
  final InAppLocalhostServer _localhostServer = InAppLocalhostServer(
    documentRoot: 'assets/solara_web',
    port: _port,
  );
  late final PullToRefreshController _pullToRefreshController =
      PullToRefreshController(onRefresh: () async {
    await _controller?.reload();
    _pullToRefreshController.endRefreshing();
  });

  InAppWebViewController? _controller;
  double _progress = 0;
  bool _serverReady = false;
  String? _errorMessage;

  bool get _supportsWebView {
    if (kIsWeb) {
      return false;
    }
    final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isFlutterTest) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  void initState() {
    super.initState();
    _bootLocalServer();
  }

  Future<void> _bootLocalServer() async {
    if (!_supportsWebView) {
      setState(() => _errorMessage = 'This experience requires an iOS/Android device.');
      return;
    }
    try {
      await _localhostServer.start();
      if (mounted) {
        setState(() => _serverReady = true);
      }
    } catch (error) {
      setState(() => _errorMessage = 'Unable to boot Solara assets: $error');
    }
  }

  @override
  void dispose() {
    _localhostServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _errorMessage != null
              ? _ErrorBanner(message: _errorMessage!)
              : !_serverReady
                  ? const _LoadingState()
                  : _SolaraFrame(
                      progress: _progress,
                      child: _buildPlayer(),
                    ),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(46),
      child: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('http://localhost:$_port/index.html'),
        ),
        initialSettings: InAppWebViewSettings(
          allowsInlineMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          useOnDownloadStart: true,
          disallowOverScroll: false,
          transparentBackground: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        pullToRefreshController: _pullToRefreshController,
        onReceivedError: (controller, request, error) {
          setState(() {
            _errorMessage = error.description;
          });
        },
        onProgressChanged: (controller, progress) {
          setState(() {
            _progress = progress / 100;
          });
          if (progress >= 100) {
            _pullToRefreshController.endRefreshing();
          }
        },
      ),
    );
  }
}

class _SolaraFrame extends StatelessWidget {
  const _SolaraFrame({required this.child, required this.progress});

  final Widget child;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF32101C), Color(0xFF050505)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              math.min(math.max(constraints.maxWidth - 32, 320.0), 430.0);
          final height = math.max(constraints.maxHeight - 32, 720.0);
          return Align(
            child: Container(
              width: width,
              height: height.clamp(720.0, 960.0).toDouble(),
              decoration: BoxDecoration(
                color: const Color(0xFF050608),
                borderRadius: BorderRadius.circular(48),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 30),
                    blurRadius: 60,
                    spreadRadius: -20,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: progress >= 1 ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: SizedBox(
                          width: width - 64,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value: progress,
                              backgroundColor: Colors.white10,
                              color: const Color(0xFFFF6B5F),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Booting Solara assets…',
            style: TextStyle(letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.shade200.withOpacity(.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 38),
              const SizedBox(height: 12),
              Text(
                'Solara player unavailable',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
