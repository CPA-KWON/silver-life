import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
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
    this.species = 'dog',
    this.interactive = true,
    this.entrance = false,
  });
  final String stage;
  final String species;
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
  String? _lastConfiguration;
  Timer? _timeout;
  Timer? _handshake;
  bool _probing = false;
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

  // The model can finish while the platform channel is still attaching.
  // Confirm readiness independently until ready/failed, then stop polling.
  void _connect(WebViewController web) {
    _web = web;
    _handshake?.cancel();
    if (!_visible || !_foreground || _ready || _failed) return;
    _handshake = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!mounted || _ready || _failed || _web != web) {
        _handshake?.cancel();
        return;
      }
      if (_probing || !_visible || !_foreground) return;
      _probing = true;
      try {
        final raw = await web.runJavaScriptReturningResult(
          'JSON.stringify(window.kongi?.status() ?? {bridge: false})',
        );
        dynamic value = raw;
        for (var i = 0; i < 2 && value is String; i++) {
          value = jsonDecode(value);
        }
        if (value is Map && value['loaded'] == true) {
          _message(const JavaScriptMessage(message: '{"type":"ready"}'));
        }
      } catch (_) {
        // The local WebView may still be loading; the bounded handshake retries.
      } finally {
        _probing = false;
      }
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
      _syncPreparation();
      _send();
    }
  }

  @override
  void didUpdateWidget(PetScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage ||
        oldWidget.species != widget.species) {
      _ready = _failed = false;
      _web = null;
      _lastConfiguration = null;
      _entrance = false;
      _startTimeout();
    }
    _send();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPreparation();
    _send();
  }

  void _syncPreparation() {
    if (!_visible || !_foreground) {
      _timeout?.cancel();
      _handshake?.cancel();
    } else if (!_ready && !_failed) {
      _startTimeout();
      if (_web != null) _connect(_web!);
    }
  }

  Map<String, Object> configuration({bool entrance = false}) => {
    'outfit': widget.outfit.toList()..sort(),
    'motion': entrance
        ? 'Jump'
        : switch (widget.motion) {
            'hello' => 'Jump',
            'eat' || 'eating' => 'Eat',
            'walk' => 'Walk',
            'happy' => 'Happy',
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
      final payload = jsonEncode(configuration(entrance: entrance));
      if (payload == _lastConfiguration) return;
      await web.runJavaScript('window.kongi?.configure($payload);');
      _lastConfiguration = payload;
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  double _pendingRotation = 0;
  bool _rotationScheduled = false;

  // One update per Flutter frame, with no queued JS calls or widget rebuilds.
  // Flutter owns the horizontal gesture so vertical drags still scroll the page.
  void rotateBy(double pixels) {
    if (!_ready || _failed || _web == null) return;
    _pendingRotation += pixels;
    if (_rotationScheduled) return;
    _rotationScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) async {
      final delta = _pendingRotation;
      _pendingRotation = 0;
      try {
        if (mounted && _ready && !_failed) {
          await _web?.runJavaScript('window.kongi?.rotate($delta);');
        }
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      } finally {
        _rotationScheduled = false;
        if (mounted && _pendingRotation != 0) rotateBy(0);
      }
    });
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
      _handshake?.cancel();
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
      _lastConfiguration = null;
      _attempt++;
    });
    _startTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _handshake?.cancel();
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
                Image.asset(
                  widget.species == 'cat'
                      ? 'assets/pet/expansion/cat_${widget.stage == 'junior' ? 'teen' : widget.stage}_34.png'
                      : 'assets/pet/${widget.stage}/angle.png',
                ),
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
                key: ValueKey('${widget.species}-${widget.stage}-$_attempt'),
                src: 'assets/pet/models/${widget.species}_${widget.stage}.glb',
                alt: '반려동물 입체 모델. 손가락을 좌우로 움직여 돌려보세요.',
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
                onWebViewCreated: _connect,
              ),
            if (!_ready)
              const ColoredBox(
                color: AppColors.blueTint,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(semanticsLabel: '3D 준비 중'),
                      SizedBox(height: 12),
                      Text('반려동물이 오고 있어요'),
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
