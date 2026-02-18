import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoadingPepperScreen extends StatefulWidget {
  const LoadingPepperScreen({
    super.key,
    this.assetPath = 'assets/icons/pimiento.svg',
    this.size = 140,
  });

  final String assetPath;
  final double size;

  @override
  State<LoadingPepperScreen> createState() => _LoadingPepperScreenState();
}

class _LoadingPepperScreenState extends State<LoadingPepperScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounce;

  late final AnimationController _colorCtrl;
  late final Animation<Color?> _color;

  @override
  void initState() {
    super.initState();

    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _bounce = CurvedAnimation(
      parent: _bounceCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _colorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _color = TweenSequence<Color?>([
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFF2ECC71),
          end: const Color(0xFFF1C40F),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFFF1C40F),
          end: const Color(0xFFE74C3C),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFFE74C3C),
          end: const Color(0xFF2ECC71),
        ),
        weight: 1,
      ),
    ]).animate(CurvedAnimation(parent: _colorCtrl, curve: Curves.linear));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_bounceCtrl, _colorCtrl]),
            builder: (context, _) {
              final y = (1 - _bounce.value) * 22;
              final scale = 0.96 + (_bounce.value * 0.08);

              return Transform.translate(
                offset: Offset(0, y),
                child: Transform.scale(
                  scale: scale,
                  child: SvgPicture.asset(
                    widget.assetPath,
                    width: widget.size,
                    height: widget.size,
                    colorFilter: ColorFilter.mode(
                      _color.value ?? const Color(0xFF2ECC71),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
