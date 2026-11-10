import 'dart:math' as math;
import 'dart:typed_data' show Float32List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

part 'focus_mode_room.dart';

const _cap = 1 / 1.32;
const _width = _cap * 1.85;
const _rim = _cap * .046;
const _window = _cap - 2 * _rim;
const _radius = _window / 2 - _cap * .032;
const _travel = _width / 2 - _rim - _radius - _cap * .018;

double _unit(num x) => x.clamp(0.0, 1.0).toDouble();
double _mix(double a, double b, double x) => a + (b - a) * x;
double _smooth(double a, double b, double x) {
  final t = _unit((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

/// A pixel-art study with a draggable glass switch. Give it bounded space.
class FocusModeSwitch extends StatefulWidget {
  const FocusModeSwitch(
      {super.key,
      this.initiallyFocused = false,
      this.focused,
      this.animateIdle = true,
      this.showStage = true,
      this.onChanged});

  final bool initiallyFocused;
  final bool? focused;
  final bool animateIdle;
  final bool showStage;

  final ValueChanged<bool>? onChanged;

  @override
  State<FocusModeSwitch> createState() => _FocusModeSwitchState();
}

class _FocusModeSwitchState extends State<FocusModeSwitch>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _scene = _FocusScene();
  late final Ticker _ticker;
  (ui.FragmentShader, ui.FragmentShader)? _shaders;
  Duration? _last;
  bool _checked = false, _dragging = false, _pressed = false;
  bool _returning = false, _reduced = false, _active = true, _enabled = true;
  double _x = 0, _target = 0, _velocity = 0, _lift = 0;
  double _stretch = 0, _stretchVelocity = 0, _hold = 0, _departure = 21.5;
  double _t = 0, _worldAt = -1, _fastAt = -10;
  double _dragHeight = 1;
  String _phase = '可以打扰';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    if (widget.focused ?? widget.initiallyFocused) {
      _checked = true;
      _phase = '专注';
      _x = _target = _scene.x = 1;
    }
    _scene.update(_checked ? 21.5 : 12, 0, 0, false, false);
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/focus_lens.frag');
      if (!mounted) return;
      _shaders = (program.fragmentShader(), program.fragmentShader());
      _scene.repaint();
    } catch (error) {
      debugPrint('Focus lens shader: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _enabled = TickerMode.valuesOf(context).enabled;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FocusModeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = widget.focused;
    if (focused != null && focused != _checked) {
      _checked = focused;
      _setTarget(focused ? 1 : 0, commit: false);
    }
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  bool get _moving =>
      _pressed ||
      _x != _target ||
      _velocity != 0 ||
      _lift > .002 ||
      _stretch.abs() > .002 ||
      _stretchVelocity.abs() > .02;

  void _syncTicker() {
    if (_enabled && _active && (widget.animateIdle && !_reduced || _moving)) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      _last = null;
    }
  }

  void _setTarget(double value, {bool commit = true}) {
    if (value < _target && !_returning && (_x >= .995 || _hold > 0)) {
      _returning = true;
      _departure = 21.5 + 1.9 * _hold / 26;
      _hold = 0;
    }
    _target = _unit(value);
    if (commit && (_target >= .5) != _checked) {
      setState(() => _checked = _target >= .5);
      widget.onChanged?.call(_checked);
    }
    _syncTicker();
  }

  void _toggle() => _setTarget(_checked ? 0 : 1);

  void _tick(Duration elapsed) {
    final dt =
        ((elapsed - (_last ?? elapsed)).inMicroseconds / 1e6).clamp(.0001, .05);
    _last = elapsed;
    _t += dt;
    final before = _x;
    if (_dragging) {
      _x = _mix(_x, _target, 1 - math.exp(-34 * dt));
    } else {
      final omega = _reduced ? 16 : 9.5;
      final offset = _x - _target;
      final b = _velocity + omega * offset;
      final decay = math.exp(-omega * dt);
      _x = _target + (offset + b * dt) * decay;
      _velocity = (_velocity - omega * b * dt) * decay;
      if ((_x - _target).abs() < .001 && _velocity.abs() < .018) {
        if (!_reduced && _x != _target && (_target == 0 || _target == 1)) {
          _stretchVelocity += 1.9;
        }
        _x = _target;
        _velocity = 0;
      }
    }
    _x = _unit(_x);
    _lift = _mix(_lift, _pressed ? 1 : 0, 1 - math.exp(-14 * dt));
    if (_reduced) {
      _stretch = 0;
      _stretchVelocity = 0;
    } else {
      final wanted = math.min(1.4, ((_x - before) / dt).abs() * .42);
      final steps = (dt / .008).ceil();
      final step = dt / steps;
      for (var i = 0; i < steps; i++) {
        _stretchVelocity +=
            (170 * (wanted - _stretch) - 11 * _stretchVelocity) * step;
        _stretch += _stretchVelocity * step;
      }
    }
    if (_x >= .999 && _target == 1 && !_dragging) {
      if (widget.animateIdle) _hold = math.min(26, _hold + dt);
      _returning = false;
    }
    if (_x <= .001 && _target == 0 && !_dragging) {
      _returning = false;
      _hold = 0;
    }
    final h = (_returning
            ? _mix(36, _departure, _x)
            : 12 + 9.5 * _x + 1.9 * _hold / 26) %
        24;
    final phase = _returning
        ? h < 7.7
            ? '休息'
            : '结束专注'
        : _x >= .995
            ? '专注'
            : h < 14
                ? '可以打扰'
                : '进入专注';
    if (phase != _phase) setState(() => _phase = phase);
    _scene
      ..x = _x
      ..lift = _lift
      ..stretch = _stretch;
    if (_t - _worldAt >= 1 / 30 - .002 ||
        !widget.animateIdle && !_moving ||
        _reduced && !_moving) {
      _scene.update(
          h, _t, math.min(.05, _t - _worldAt), _reduced, _t - _fastAt < .48);
      _worldAt = _t;
    }
    _scene.repaint();
    if (_reduced || !widget.animateIdle) _syncTicker();
  }

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _scene.dispose();
    _shaders?.$1.dispose();
    _shaders?.$2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final control = Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth * (widget.showStage ? .6 : 1);
          _dragHeight = width / 1.6439;
          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                  painter: _FocusPainter(_scene, () => _shaders, dpr,
                      _dragHeight, widget.showStage)),
              Center(
                child: SizedBox(
                  width: _width * _dragHeight,
                  height: _cap * _dragHeight,
                  child: Semantics(
                    label: '专注模式',
                    value: _phase,
                    toggled: _checked,
                    liveRegion: true,
                    onTap: _toggle,
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is KeyUpEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.space ||
                            key == LogicalKeyboardKey.enter) {
                          if (event is KeyDownEvent) _toggle();
                        } else if (key == LogicalKeyboardKey.arrowLeft ||
                            key == LogicalKeyboardKey.arrowDown) {
                          _setTarget(_target - .04);
                        } else if (key == LogicalKeyboardKey.arrowRight ||
                            key == LogicalKeyboardKey.arrowUp) {
                          _setTarget(_target + .04);
                        } else {
                          return KeyEventResult.ignored;
                        }
                        return KeyEventResult.handled;
                      },
                      child: Builder(builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return MouseRegion(
                          cursor: _pressed
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(_dragHeight),
                              border: focused
                                  ? Border.all(
                                      color: const Color(0xffefa02c), width: 2)
                                  : null,
                            ),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTapDown: (_) => _press(true),
                              onTapCancel: () {
                                if (!_dragging) _press(false);
                              },
                              onTapUp: (_) => _press(false),
                              onTap: _toggle,
                              onHorizontalDragStart: (_) {
                                _dragging = true;
                                _velocity = 0;
                                _press(true);
                              },
                              onHorizontalDragUpdate: (detail) => _setTarget(
                                  _target +
                                      detail.delta.dx /
                                          (_dragHeight * 2 * _travel),
                                  commit: false),
                              onHorizontalDragEnd: (detail) {
                                _dragging = false;
                                final speed =
                                    detail.velocity.pixelsPerSecond.dx /
                                        (_dragHeight * 2 * _travel);
                                if (!_reduced &&
                                    speed.abs() > 3.4 &&
                                    _t - _fastAt > 1.5) {
                                  _fastAt = _t;
                                }
                                _velocity = speed.clamp(-3.0, 3.0);
                                _press(false);
                                _setTarget(_x + _velocity * .09 >= .5 ? 1 : 0);
                              },
                              onHorizontalDragCancel: () {
                                _dragging = false;
                                _press(false);
                                _setTarget(_checked ? 1 : 0);
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
    return widget.showStage
        ? ColoredBox(color: const Color(0xffe9e9e9), child: control)
        : control;
  }
}
