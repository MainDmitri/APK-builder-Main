import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fades and slides its child in once, after [delay] (staggered lists).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 480);
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + _duration;
    _controller = AnimationController(vsync: this, duration: total)..forward();
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    _curve = CurvedAnimation(parent: _controller, curve: Interval(start, 1, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Main call-to-action: gradient, glow and a press animation.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.height = 56,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null && !widget.loading;
    final foreground = enabled ? Colors.white : scheme.onSurfaceVariant;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: enabled ? AppColors.gradient : null,
          color: enabled ? null : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [BoxShadow(color: AppColors.violet.withValues(alpha: 0.45), blurRadius: 26, offset: const Offset(0, 10))]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? widget.onPressed : null,
            onHighlightChanged: (v) => setState(() => _pressed = v && enabled),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: widget.loading
                      ? SizedBox.square(
                          key: const ValueKey('loading'),
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: foreground),
                        )
                      : Icon(widget.icon, key: const ValueKey('icon'), color: foreground),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.2),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded progress bar with the brand gradient. [value] null → animated
/// "working" stripe.
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({super.key, required this.value, this.height = 10, this.color});

  final double? value;
  final double height;

  /// Solid color instead of the gradient (e.g. errors, pauses).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    final fill = BoxDecoration(
      gradient: color == null ? AppColors.gradient : null,
      color: color,
      borderRadius: BorderRadius.circular(height),
      boxShadow: [BoxShadow(color: (color ?? AppColors.violet).withValues(alpha: 0.5), blurRadius: 12)],
    );
    return Container(
      height: height,
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(height)),
      child: value == null
          ? _IndeterminateStripe(decoration: fill)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value!.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: DecoratedBox(decoration: fill),
              ),
            ),
    );
  }
}

class _IndeterminateStripe extends StatefulWidget {
  const _IndeterminateStripe({required this.decoration});

  final BoxDecoration decoration;

  @override
  State<_IndeterminateStripe> createState() => _IndeterminateStripeState();
}

class _IndeterminateStripeState extends State<_IndeterminateStripe> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.decoration.borderRadius!,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Align(
          alignment: Alignment(-1.8 + 3.6 * Curves.easeInOut.transform(_controller.value), 0),
          child: FractionallySizedBox(widthFactor: 0.38, child: DecoratedBox(decoration: widget.decoration)),
        ),
      ),
    );
  }
}

/// Square badge with the brand gradient behind a white icon.
class GradientBadge extends StatelessWidget {
  const GradientBadge({super.key, required this.icon, this.size = 38});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [BoxShadow(color: AppColors.violet.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// Text painted with the brand gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => AppColors.gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style),
    );
  }
}

/// Green check that pops in with an elastic scale.
class SuccessCheck extends StatelessWidget {
  const SuccessCheck({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 18)],
        ),
        child: Icon(Icons.check_rounded, color: Colors.black, size: size * 0.62),
      ),
    );
  }
}
