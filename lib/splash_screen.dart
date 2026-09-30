import 'dart:ui';

import 'package:flutter/material.dart';
import 'app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.nextPageBuilder,
    this.duration = const Duration(milliseconds: 900),
    this.errorBuilder,
  });

  final Future<Widget> Function() nextPageBuilder;
  final Duration duration;
  final Widget Function(BuildContext context, Object error, VoidCallback retry)?
  errorBuilder;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color _backgroundColor = QuickDropColors.primaryLight;
  static const String _logoAsset = 'assets/logos/quickdrop_go_logo.png';
  static const List<_SplashCategoryAsset> _categoryAssets = [
    _SplashCategoryAsset(
      assetPath: 'assets/banners/grocery.png',
      beginOffset: Offset(-1.7, -1.25),
      start: 0.00,
    ),
    _SplashCategoryAsset(
      assetPath: 'assets/banners/food.png',
      beginOffset: Offset(1.8, -1.15),
      start: 0.08,
    ),
    _SplashCategoryAsset(
      assetPath: 'assets/banners/gifts.png',
      beginOffset: Offset(-1.95, 0.10),
      start: 0.16,
    ),
    _SplashCategoryAsset(
      assetPath: 'assets/banners/cosmetics.png',
      beginOffset: Offset(1.85, 0.25),
      start: 0.24,
    ),
    _SplashCategoryAsset(
      assetPath: 'assets/banners/electronics.png',
      beginOffset: Offset(-1.3, 1.55),
      start: 0.32,
    ),
    _SplashCategoryAsset(
      assetPath: 'assets/banners/parcel_delivery.png',
      beginOffset: Offset(1.45, 1.6),
      start: 0.40,
    ),
  ];

  late final AnimationController _controller;
  Object? _error;
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _startFlow();
  }

  Future<void> _startFlow() async {
    final int runId = ++_runId;

    setState(() {
      _error = null;
    });

    _controller
      ..stop()
      ..reset();

    try {
      final nextPageFuture = widget.nextPageBuilder();
      await Future.wait<void>([
        _controller.forward().orCancel,
        nextPageFuture.then((_) {}),
      ]);

      final nextPage = await nextPageFuture;
      if (!mounted || runId != _runId) {
        return;
      }

      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (context, animation, secondaryAnimation) => nextPage,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curve),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted || runId != _runId) {
        return;
      }

      setState(() {
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, _startFlow);
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final logoOpacity = _intervalValue(0.0, 0.78, Curves.easeOutCubic);
          final logoScaleProgress = _intervalValue(0.0, 0.86, Curves.easeOutBack);
          final logoScale = lerpDouble(0.86, 1.0, logoScaleProgress) ?? 1.0;
          final textOpacity = _intervalValue(0.32, 0.92, Curves.easeOut);
          final glowStrength = 18 + (18 * _intervalValue(0.18, 0.72));

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 1.0,
                    colors: [
                      Colors.white.withValues(alpha: 0.30),
                      _backgroundColor,
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -80,
                left: -40,
                child: _AmbientGlow(size: 220, opacity: 0.14),
              ),
              Positioned(
                right: -55,
                bottom: -70,
                child: _AmbientGlow(size: 260, opacity: 0.10),
              ),
              ..._buildFlyingCategories(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: logoOpacity,
                      child: Transform.scale(
                        scale: logoScale,
                        child: Container(
                          width: 144,
                          height: 144,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.95),
                                blurRadius: glowStrength,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.55),
                                blurRadius: glowStrength * 1.6,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Image.asset(
                                  _logoAsset,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: textOpacity,
                      child: const Text(
                        'QuickDrop',
                        style: TextStyle(
                          color: QuickDropColors.primaryDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildFlyingCategories() {
    return _categoryAssets.map((item) {
      final progress = _intervalValue(item.start, 0.82, Curves.easeInOutCubic);
      final travel = Curves.easeInOutCubic.transform(progress);
      final fadeOut = progress < 0.72 ? 1.0 : 1.0 - ((progress - 0.72) / 0.28);
      final scale = lerpDouble(1.0, 0.24, travel) ?? 0.24;
      final translation = Offset(
        item.beginOffset.dx * 120 * (1 - travel),
        item.beginOffset.dy * 120 * (1 - travel),
      );

      return Center(
        child: Transform.translate(
          offset: translation,
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: fadeOut.clamp(0.0, 1.0),
              child: Container(
                width: 88,
                height: 88,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE0B100).withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Image.asset(item.assetPath, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  double _intervalValue(double begin, double end, [Curve curve = Curves.linear]) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve),
    ).value;
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _SplashCategoryAsset {
  const _SplashCategoryAsset({
    required this.assetPath,
    required this.beginOffset,
    required this.start,
  });

  final String assetPath;
  final Offset beginOffset;
  final double start;
}