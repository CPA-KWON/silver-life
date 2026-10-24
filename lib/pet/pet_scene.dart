import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';

/// The renderer and GLBs are bundled in the APK. No model download or API key.
class PetScene extends StatefulWidget {
  const PetScene({
    super.key,
    required this.stage,
    required this.outfit,
    this.motion,
    this.interactive = true,
    this.entrance = false,
  });
  final String stage;
  final Set<String> outfit;
  final String? motion;
  final bool interactive;
  final bool entrance;

  static bool get supported =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<PetScene> createState() => PetSceneState();
}

class PetSceneState extends State<PetScene> with WidgetsBindingObserver {
  static final _script = rootBundle.loadString(
    'assets/pet/scene/kongi_scene.js',
  );
  WebViewController? _web;
  Timer? _timeout;
  bool _ready = false, _failed = false, _imageOnly = false, _foreground = true;
  bool _reduceMotion = false;
  bool _visible = true;
  bool _entrance = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entrance = widget.entrance || widget.motion == 'hello';
    _startTimeout();
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final visible = TickerMode.valuesOf(context).enabled;
    if (_reduceMotion != reduce || _visible != visible) {
      _reduceMotion = reduce;
      _visible = visible;
      if (!_visible) {
        _timeout?.cancel();
      } else if (!_ready && !_failed) {
        _startTimeout();
      }
      _send();
    }
  }

  @override
  void didUpdateWidget(PetScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) {
      _ready = _failed = false;
      _web = null;
      _entrance = false;
      _startTimeout();
    }
    _send();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _send();
  }

  Map<String, Object> configuration({bool entrance = false}) => {
    'outfit': widget.outfit.toList()..sort(),
    'motion': entrance
        ? 'Jump'
        : switch (widget.motion) {
            'hello' => 'Jump',
            'eat' => 'Eat',
            'walk' => 'Walk',
            _ => 'Idle',
          },
    'interactive': widget.interactive,
    'reducedMotion': _reduceMotion,
    'paused': !_foreground || !_visible,
  };

  Future<void> _send({bool entrance = false}) async {
    final web = _web;
    if (!mounted || !_ready || web == null || _failed) return;
    try {
      await web.runJavaScript(
        'window.kongi?.configure(${jsonEncode(configuration(entrance: entrance))});',
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> view(String angle) async {
    if (!_ready || _failed) return;
    try {
      await _web?.runJavaScript('window.kongi?.view(${jsonEncode(angle)});');
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _message(JavaScriptMessage message) {
    if (!mounted) return;
    final data = jsonDecode(message.message) as Map<String, dynamic>;
    if (data['type'] == 'ready') {
      _timeout?.cancel();
      setState(() {
        _ready = true;
        _failed = false;
      });
      _send(entrance: _entrance);
      _entrance = false;
    } else if (data['type'] == 'error') {
      _timeout?.cancel();
      setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() {
      _ready = _failed = false;
      _web = null;
      _attempt++;
    });
    _startTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _web = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_imageOnly) {
      return Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/pet/${widget.stage}/angle.png'),
                for (final id in ['knit', 'hat', 'flower'])
                  if (widget.outfit.contains(id))
                    Image.asset('assets/pet/${widget.stage}/${id}_angle.png'),
              ],
            ),
          ),
          const Text('2D 이미지로 보고 있어요', textAlign: TextAlign.center),
        ],
      );
    }
    return FutureBuilder<String>(
      future: _script,
      builder: (c, snapshot) {
        if (_failed || snapshot.hasError) {
          return SingleChildScrollView(
            child: Column(
              children: [
                const Text('3D를 불러오지 못했어요.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _retry, child: const Text('다시 불러오기')),
                TextButton(
                  onPressed: () => setState(() => _imageOnly = true),
                  child: const Text('2D 이미지로 보기'),
                ),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (snapshot.hasData)
              ModelViewer(
                key: ValueKey('${widget.stage}-$_attempt'),
                src: 'assets/pet/models/${widget.stage}.glb',
                alt: '콩이 입체 모델. 손가락을 좌우로 움직여 돌려보세요.',
                ar: false,
                loading: Loading.eager,
                autoPlay: false,
                autoRotate: false,
                interactionPrompt: InteractionPrompt.none,
                cameraControls: widget.interactive,
                disablePan: true,
                disableZoom: true,
                cameraOrbit: '25deg 80deg 5.4m',
                cameraTarget: '0m 1.25m 0m',
                fieldOfView: '32deg',
                // Keep the same viewing height while allowing a full horizontal turn.
                minCameraOrbit: 'auto 80deg 5.4m',
                maxCameraOrbit: 'auto 80deg 5.4m',
                environmentImage: 'neutral',
                exposure: 1.1,
                shadowIntensity: .6,
                debugLogging: false,
                relatedCss: 'body { overflow: hidden; } model-viewer { --poster-color: transparent; }',
                relatedJs: snapshot.data!,
                javascriptChannels: {
                  JavascriptChannel('PetScene', onMessageReceived: _message),
                },
                onWebViewCreated: (web) => _web = web,
              ),
            if (!_ready)
              const ColoredBox(
                color: AppColors.blueTint,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(semanticsLabel: '콩이 3D 준비 중'),
                      SizedBox(height: 12),
                      Text('콩이가 오고 있어요'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
