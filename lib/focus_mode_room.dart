part of 'focus_mode_switch.dart';

const _colors = [
  0xffb9b09e,
  0xffd6cdba,
  0xfff0e7d4,
  0xfffefaf0,
  0xff424e16,
  0xff637039,
  0xff86945c,
  0xffaab980,
  0xff080a2d,
  0xff181d42,
  0xff2a3259,
  0xff464f79,
  0xff4f657f,
  0xff7188a4,
  0xff95adca,
  0xffbad4f2,
  0xff88570b,
  0xffc5821c,
  0xfffbab3b,
  0xfffddfbe
];
const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const _hours = [0, 1.5, 2, 2.5, 3, 3.6, 10, 15, 17, 18, 19, 20.3, 24];
const _columns = [3, 3, 3, 2, 1, 0, 0, 0, 1, 1, 2, 3, 3];
const _day = 32, _sun = 64, _warm = 96, _shade = 128;

class _Message {
  _Message(this.start, this.blocked, this.burst, this.lane);
  final double start, lane;
  final bool blocked, burst;
  bool landed = false;
}

class _FocusScene extends ChangeNotifier {
  static const width = 220, height = 140, gw = 72, gh = 46;
  final pixels = Uint8List(width * height);
  final rgba = Uint8List(width * (height + gh) * 4);
  final _field = Float32List(gw * gh * 3);
  final _temp = Float32List(gw * gh * 3);
  final _near = Float32List(gw * gh * 3);
  final _far = Float32List(gw * gh * 3);
  double lampX = 140, lampY = 54;
  bool _releasing = false;
  final random = math.Random();
  final messages = <_Message>[];
  ui.Image? room;
  bool _busy = false, _disposed = false;
  double x = 0, lift = 0, stretch = 0, night = 0, lamp = 0;
  double _next = 0, _burst = 0, _ping = -1, _typed = 0, _blink = 0;
  int _backlog = 0, _chat = 2;
  bool _wasCode = false;

  void repaint() => notifyListeners();

  void _dot(num x, num y, int color) {
    final xx = x.round() + 14, yy = y.round() + 14;
    if (xx >= 0 && xx < width && yy >= 0 && yy < height) {
      pixels[yy * width + xx] = color;
    }
  }

  void _rect(num x, num y, int w, int h, int color) {
    final xx = x.round() + 14, yy = y.round() + 14;
    final a = math.max(0, xx), b = math.min(width, xx + w);
    if (a >= b) return;
    for (var j = math.max(0, yy); j < math.min(height, yy + h); j++) {
      pixels.fillRange(j * width + a, j * width + b, color);
    }
  }

  void _line(num x, num y, num endX, num endY, int color) {
    final steps =
        math.max(1, math.max((endX - x).abs(), (endY - y).abs()).ceil());
    for (var i = 0; i <= steps; i++) {
      _dot(x + (endX - x) * i / steps, y + (endY - y) * i / steps, color);
    }
  }

  void _oval(num x, num y, int rx, int ry, int color) {
    for (var j = -ry; j <= ry; j++) {
      final r = (rx * math.sqrt(1 - j * j / (ry * ry))).floor();
      _rect(x - r, y + j, 2 * r + 1, 1, color);
    }
  }

  void _steam(num x, num y, double t, double amount) {
    for (var i = 0; i < 13; i++) {
      final age = (t * .65 + i * .17) % 1;
      final xx = x.round() + (math.sin(i * 2 + age * 5) * age * 3).round();
      final yy = y.round() - (age * 12).floor();
      if (_bayer[(yy & 3) * 4 + (xx & 3)] < 16 * amount * (1 - age)) {
        _dot(xx, yy, 15);
      }
    }
  }

  void update(double h, double t, double dt, bool reduced, bool shock) {
    night = _unit(_smooth(17.4, 20.2, h) + 1 - _smooth(1.5, 3.6, h));
    final morning = h < 12;
    final open = morning ? _smooth(7, 7.7, h) : 1 - _smooth(15.2, 15.9, h);
    final blind = morning ? 1 - _smooth(1.4, 3.4, h) : _smooth(16, 19.2, h);
    lamp = morning
        ? 1 - _smooth(1.66, 1.7, h)
        : h < 18.4
            ? 0
            : h < 18.4 + 4 / 12
                ? ((h - 18.4) * 12).floor().isEven
                    ? 1
                    : 0
                : 1;
    final code = h >= 14.7 || h < 7.7, typing = h >= 15.4, deep = h >= 21.5;
    if (!code || !_wasCode) _typed = 0;
    if (typing) _typed += dt * (deep ? 14 : 8);
    _wasCode = code;
    if (!morning && !deep && t >= _next) {
      final blocked = open < .45;
      messages.add(_Message(t, blocked, false, random.nextDouble()));
      if (blocked) _backlog++;
      _next = t + 1.5 + random.nextDouble() * 1.1;
    }
    if (morning && h < 7.7) {
      _releasing = true;
      _backlog = math.max(_backlog, 4);
      _burst = t;
    }
    if (_releasing && h >= 7.7 && h < 14 && _backlog > 0 && t >= _burst) {
      messages.add(_Message(t, false, true, random.nextDouble()));
      _backlog--;
      if (_backlog == 0) _releasing = false;
      _burst = t + .14;
    }
    for (final m in messages) {
      if (!m.blocked && !m.landed && t - m.start >= (m.burst ? .48 : .92)) {
        m.landed = true;
        _ping = t + .67;
        _chat++;
      }
    }
    messages.removeWhere((m) => t - m.start >= (m.blocked ? 1.8 : 1));
    final ping = t < _ping;
    if (t > _blink + .12) _blink = t + 2 + random.nextDouble() * 4;

    pixels.fillRange(0, pixels.length, 2);
    _rect(-14, -14, width, 18, 1);
    _rect(-14, 4, width, 2, 3);
    _rect(-14, 6, width, 1, 1);
    _rect(-14, 74, width, 18, 3);
    _rect(-14, 73, width, 1, 1);
    for (var i = -16; i < 206; i += 8) {
      _rect(i, 76, 1, 16, 2);
    }
    _rect(-14, 92, width, 4, 1);
    for (var y = 96; y < 126; y++) {
      _rect(-14, y, width, 1, [96, 101, 109, 121].contains(y) ? 0 : 1);
      for (var i = -8; i <= 8; i++) {
        _dot(96 + i * (15 + (y - 96) * .75) + (y >= 109 ? 9 : 0), y, _shade);
      }
    }
    _oval(105, 104, 59, 8, _shade);
    _oval(104, 102, 58, 8, 13);
    _oval(104, 102, 53, 6, 14);
    for (var i = 61; i < 150; i += 4) {
      _dot(i, 102, 13);
      _dot(i + 1, 103, 13);
    }
    for (var y = 96; y < 119; y++) {
      final left = (9 + (y - 96) * 2.2).floor();
      for (var x = left; x < left + 54; x++) {
        if ((blind < .02 || (x - left) % 8 < 2) &&
            _bayer[(y & 3) * 4 + (x & 3)] <
                16 * (1 - night) * (1 - blind * .35)) {
          final i = (y + 14) * width + x + 14;
          pixels[i] = (pixels[i] & 31) | _sun;
        }
      }
    }
    _rect(21, 19, 41, 44, 1 | _shade);
    _rect(22, 20, 39, 42, 3);
    for (var y = 23; y < 59; y++) {
      for (var x = 25; x < 58; x++) {
        final ridge = 37 + math.sin(x * .27) * 3 + math.sin(x * .53) * 2;
        _dot(
            x,
            y,
            _day |
                (y > 45 + math.sin(x * .23) * 3
                    ? 7
                    : y > ridge
                        ? 14
                        : 15));
        final cloud = (x + 42 - (reduced ? 0 : t * .65) % 42) % 42;
        if (y >= 26 && y < 29 && cloud > 2 && cloud < 12 - (y - 27).abs() * 3) {
          _dot(x, y, 3 | _day);
        }
      }
    }
    _rect(37, 46, 12, 8, 2 | _day);
    _rect(40, 49, 3, 4, 13 | _day);
    for (var i = 0; i < 5; i++) {
      _rect(36 + i, 45 - i, 14 - i * 2, 1, 9 | _day);
    }
    for (final (x, y) in [(30, 47), (53, 48)]) {
      _rect(x, y, 1, 7, 5 | _day);
      _oval(x, y - 3, 4, 5, 5 | _day);
      _oval(x - 1, y - 4, 3, 3, 6 | _day);
    }
    if (!reduced && t % 17 < 4) {
      final x = 27 + (t % 17 * 7).floor(), y = 31 + math.sin(t * 4);
      _line(x - 2, y - 1, x, y, 9 | _day);
      _line(x, y, x + 2, y - 1, 9 | _day);
    }
    final sash = (41 - open * 17).round();
    _rect(25, 40, 33, 1, 2);
    _rect(25, sash, 33, 2, 3);
    _rect(41, 23, 1, 18, 3);
    _rect(41, sash + 2, 1, 17, 3);
    for (var y = 23; y < 23 + (blind * 36).round(); y++) {
      if ((y - 23) % 3 != 2) _rect(25, y, 33, 1, (y - 23) % 3 == 0 ? 14 : 13);
    }
    _rect(20, 61, 43, 2, 3);
    _rect(21, 63, 41, 2, 1);
    _rect(51, 57, 7, 4, 17);
    final sway = reduced ? 0 : math.sin(t * 4) * open;
    _line(54, 57, 54 + sway, 50, 5);
    _oval(52 + sway, 53, 2, 1, 6);
    _oval(56 + sway, 51, 2, 1, 7);
    if (!reduced && night < .75) {
      for (var i = 0; i < 9; i++) {
        if (math.sin(t + i * 6) > 0) {
          _dot(24 + (i * 11 + t * 1.4) % 48, 65 + (i * 13 + t * .8) % 35,
              3 | _sun);
        }
      }
    }
    _rect(76, 24, 17, 13, 5);
    _rect(77, 25, 15, 11, 3);
    _rect(79, 27, 11, 7, 14);
    _oval(86, 29, 2, 1, 19);
    _line(79, 33, 84, 29, 6);
    _line(84, 29, 89, 33, 6);
    if (lamp > 0) {
      for (var y = 55; y < 74; y++) {
        for (var x = 125; x < 152; x++) {
          final power =
              1 - math.pow((x - 140) / 15, 2) - math.pow((y - 65) / 12, 2);
          if (power * 16 > _bayer[(y & 3) * 4 + (x & 3)]) _dot(x, y, 2 | _sun);
        }
      }
    }
    _desk(code, reduced, t, ping);
    _shelf();
    _person(h, t, reduced, shock, deep, typing, ping);
    if (!reduced) {
      for (final m in messages) {
        final age = t - m.start, travel = m.burst ? .48 : .92;
        if (!m.blocked && age >= travel) continue;
        final p = _unit(age / travel), hit = m.blocked && age >= travel;
        final x = _mix(28 + m.lane * 11, m.blocked ? 55 : 75, p).round();
        final y = (_mix(38 + m.lane * 9, m.blocked ? 47 : 67, p) -
                math.sin(p * math.pi) * 13 +
                (hit ? (age - travel) * 13 : 0))
            .round();
        final w = hit ? 2 : (2 + p * 5).round(),
            hh = hit ? 4 : (2 + p * 2).round();
        for (var j = 0; j < hh; j++) {
          for (var i = 0; i < w; i++) {
            if (hit &&
                _bayer[((y + j) & 3) * 4 + ((x + i) & 3)] >
                    16 * (1 - _unit((age - travel) / .88))) {
              continue;
            }
            _dot(
                x + i,
                y + j,
                hit && age - travel < .1
                    ? 19
                    : j == 1 && i > 0 && i < w - 1
                        ? 14
                        : 3);
          }
        }
      }
    }
    _publish(h, blind, code, ping);
  }

  void _desk(bool code, bool reduced, double t, bool ping) {
    _rect(68, 70, 90, 3, 5);
    _rect(68, 70, 90, 1, 7);
    _rect(70, 73, 3, 23, 4);
    _rect(71, 73, 1, 22, 6);
    _rect(143, 73, 14, 23, 4);
    for (var y = 74; y < 93; y += 7) {
      _rect(144, y, 12, 6, 5);
      _rect(148, y + 2, 4, 1, 18);
    }
    if (lamp > 0) _rect(123, 70, 25, 1, 18 | _warm);
    _rect(112, 46, 26, 17, 9);
    _rect(113, 47, 24, 15, code ? 8 : 14);
    _rect(124, 63, 3, 5, 9);
    _rect(119, 68, 13, 1, 10);
    _rect(105, 68, 12, 1, 13);
    for (var i = 0; i < 5; i++) {
      final length = code
          ? (_typed.floor() - i * 13).clamp(0, 10 + i * 7 % 10)
          : 5 + math.max(0, _chat - 4 + i) * 7 % 13;
      _rect(
          code
              ? 115 + i % 2 * 2
              : i.isOdd
                  ? 135 - length
                  : 115,
          49 + i * 2,
          length,
          1,
          code
              ? [14, 18, 7, 15, 17][i]
              : i.isOdd
                  ? 6
                  : 3);
    }
    if (code && (reduced || t % 1 < .55)) {
      _dot(115 + _typed.floor() % 19, 50 + math.min(4, _typed ~/ 13) * 2, 15);
    }
    _rect(143, 68, 10, 2, 9);
    _rect(147, 55, 2, 13, 10);
    _line(148, 56, 144, 50, 10);
    _line(144, 50, 139, 52, 10);
    _rect(136, 52, 9, 2, 17);
    _rect(134, 54, 12, 2, lamp > 0 ? 19 | _warm : 5);
    final phone = 73 + (ping && !reduced ? math.sin(t * 70).round() : 0);
    _rect(phone, 67, 6, 3, 9);
    _rect(phone + 1, 67, 4, 2, ping ? 15 : 10);
    if (ping) _dot(phone + 5, 66, 18);
  }

  void _shelf() {
    _rect(162, 32, 29, 64, 4);
    _rect(164, 35, 24, 58, _shade);
    for (final y in [33, 51, 68, 84, 94]) {
      _rect(162, y, 29, 2, 5);
      _rect(162, y, 29, 1, 6);
    }
    _rect(162, 33, 2, 63, 5);
    _rect(189, 33, 2, 63, 5);
    for (var i = 0; i < 7; i++) {
      final y = 39 + i * 7 % 5;
      _rect(165 + i * 3, y, 2, 51 - y, [13, 17, 6, 2, 14][i % 5]);
      _dot(165 + i * 3, 48, 3);
    }
    _oval(169, 63, 4, 4, 13);
    _rect(167, 58, 5, 2, 14);
    _line(166, 62, 164, 59, 14);
    _line(172, 61, 175, 61, 13);
    _dot(175, 63, 13);
    _rect(181, 58, 5, 9, 17);
    _rect(181, 57, 5, 1, 2);
    _rect(182, 60, 3, 2, 3);
    _rect(166, 77, 10, 7, 17);
    for (var i = 0; i < 10; i += 2) {
      _rect(166 + i, 78, 1, 5, 18);
    }
    for (var i = 0; i < 5; i++) {
      _rect(178 + i * 2, 73 + i % 3, 1, 11 - i % 3, [13, 6, 2, 16, 14][i]);
    }
    _rect(173, 27, 8, 6, 17);
    _oval(176, 26, 7, 2, 6);
    _line(181, 27, 187, 40, 5);
    _line(187, 40, 185, 47, 5);
    for (var i = 0; i < 5; i++) {
      _oval(183 + i % 2 * 3, 31 + i * 3, 2, 1, 6);
    }
  }

  void _person(double h, double t, bool reduced, bool shock, bool deep,
      bool typing, bool ping) {
    final walkOut = _smooth(3.8, 4.6, h), walkBack = _smooth(6.6, 7, h);
    final standing = h >= 3.8 && h < 7,
        walking = standing && (h < 4.6 || h >= 6.6);
    final headphones = h >= 14.6 || h < .65;
    final reach = _smooth(14, 14.35, h) * (1 - _smooth(14.43, 14.75, h));
    final cupX = h >= 4.6 && h < 6.6
        ? 177.0
        : standing && h >= 6.6
            ? _mix(167, 96, walkBack)
            : 83.0;
    final cupY = cupX == 177
        ? 65
        : standing && h >= 6.6
            ? 63
            : 67;
    _rect(cupX - 2, cupY - 3, 5, 5, 3);
    _dot(cupX + 3, cupY - 2, 2);
    _dot(cupX + 3, cupY, 2);
    if (!reduced) {
      _steam(cupX, cupY - 4, t, h < 4.6 ? 0 : 1 - _smooth(19.5, 22.6, h));
      if (h >= 4.6 && h < 6.6) _steam(169, 57, t, 1);
    }
    if (!headphones) {
      _rect(139, 66, 7, 1, 3);
      _rect(139, 67, 2, 2, 3);
      _rect(144, 67, 2, 2, 3);
    }
    final blinking = !reduced && t >= _blink && t < _blink + .12;
    if (standing) {
      final x = _mix(96, 167, walkOut * (1 - walkBack)).round();
      final step =
          walking && !reduced ? math.sin(t * (shock ? 24 : 15)) * 5 : 0;
      final y = 61 - (shock ? (math.sin(t * 19).abs() * 4).round() : 0);
      _oval(x, y - 3, 4, 5, 9);
      _rect(x + 2, y - 4, 3, 5, 18);
      _dot(x + 4, y - 3, blinking ? 16 : 8);
      _rect(x - 4, y + 2, 8, 14, 6);
      _rect(x - 4, y + 2, 2, 13, 5);
      _line(x - 2, y + 15, x - step, y + 31, 9);
      _line(x + 2, y + 15, x + step, y + 31, 10);
      _rect(x - step - 1, y + 31, 4, 2, 8);
      _rect(x + step - 1, y + 31, 4, 2, 9);
      _line(x, y + 4, x + (walking ? step : 7), y + 10, 7);
      _dot(x + (walking ? step : 8), y + 10, 18);
      return;
    }
    final hy = 53 - (deep ? 1 : 0) - (shock ? 2 : 0);
    final stretch = h < 1.3 ? math.sin(math.pi * h / 1.3) : 0;
    final elbow =
        typing && !reduced ? math.sin(t * (deep ? 26 : 16)).round() : 0;
    final sip = !reduced && h >= 7 && h < 12 && t % 8 > 7.35;
    _rect(91, 76, 12, 3, 9);
    _line(96, 78, 96, 91, 9);
    _rect(89, 91, 16, 2, 9);
    _dot(89, 94, 8);
    _dot(104, 94, 8);
    _rect(91, 72, 13, 4, 9);
    _line(102, 74, 108, 86, 9);
    _rect(106, 86, 6, 2, 8);
    _rect(94, hy + 4, 5, 5, 17);
    _oval(96, hy, 4, 5, 9);
    _rect(92, hy - 1, 9, 4, 9);
    _rect(93, hy - 4, 4, 1, 10);
    _dot(91, hy + 1, 18);
    _dot(101, hy + 1, 18);
    if (ping && h < 14) {
      _dot(101, hy, 17);
      _dot(102, hy - 1, blinking ? 17 : 8);
    }
    _rect(90, hy + 7, 13, 14, 6);
    _rect(92, hy + 8, 8, 12, 7);
    final leftY = stretch > 0 ? hy + 9 - stretch * 24 : 68 + elbow;
    final rightY = stretch > 0
        ? hy + 9 - stretch * 24
        : sip
            ? hy + 4
            : 68 - elbow;
    _line(91, hy + 8, 87, leftY, 6);
    _line(102, hy + 8, 108 + reach * 31, rightY, 6);
    _dot(87, leftY, 18);
    _dot(108 + reach * 31, rightY, 18);
    if (sip) _rect(106, rightY - 3, 4, 4, 3);
    if (headphones || reach > .5) {
      final ear = hy + (shock ? 8 : 0);
      if (!shock) {
        _line(91, ear - 1, 93, ear - 5, 3);
        _rect(93, ear - 5, 7, 1, 3);
        _line(99, ear - 5, 101, ear - 1, 3);
      }
      _rect(90, ear - 1, 2, 5, 3);
      _rect(101, ear - 1, 2, 5, 3);
    }
    if (night > .35) {
      _line(100, hy - 2, 101, hy, 14);
      _line(102, hy + 8, 103, hy + 11, 13);
    }
    if (shock) {
      _rect(96, hy - 13, 1, 4, 19);
      _dot(96, hy - 8, 19);
    }
  }

  void _emit(int x, int y, double r, double g, double b, double amount) {
    final i = (((y + 14) * gh ~/ height) * gw + (x + 14) * gw ~/ width) * 3;
    _field[i] += r * amount;
    _field[i + 1] += g * amount;
    _field[i + 2] += b * amount;
  }

  void _blur(Float32List input, Float32List output, int radius) {
    final divisor = radius * 2 + 1;
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0.0;
          for (var d = -radius; d <= radius; d++) {
            sum += input[(y * gw + (x + d).clamp(0, gw - 1)) * 3 + c];
          }
          _temp[(y * gw + x) * 3 + c] = sum / divisor;
        }
      }
    }
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0.0;
          for (var d = -radius; d <= radius; d++) {
            sum += _temp[((y + d).clamp(0, gh - 1) * gw + x) * 3 + c];
          }
          output[(y * gw + x) * 3 + c] = sum / divisor;
        }
      }
    }
  }

  void _light(double blind, bool code, bool ping) {
    _field.fillRange(0, _field.length, 0);
    for (var y = 25; y < 59; y += 2) {
      for (var x = 26; x < 58; x += 2) {
        _emit(x, y, .50, .73, 1, .055 * (1 - blind * .82));
      }
    }
    for (var y = 49; y < 61; y += 2) {
      for (var x = 115; x < 136; x += 2) {
        _emit(x, y, .38, .69, 1, code ? .10 : .14);
      }
    }
    if (ping) _emit(75, 68, .45, .8, 1, .9);
    if (lamp > 0) {
      var sum = 0.0, sx = 0.0, sy = 0.0;
      for (var y = 54; y <= 70; y += 2) {
        for (var x = 132; x < 147; x += 2) {
          if ((x - 140).abs() >= 4 + (y - 54) * .35) continue;
          final power = (y == 54 ? .64 : .13) * lamp;
          _emit(x, y, 1, .63, .19, power);
          sum += power;
          sx += x * power;
          sy += y * power;
        }
      }
      lampX = sx / sum;
      lampY = sy / sum;
    }
    _blur(_field, _near, 1);
    _blur(_near, _near, 1);
    _blur(_field, _far, 3);
    _blur(_far, _far, 3);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        final i = (y * gw + x) * 3;
        final dst = ((y + height) * width + x) * 4;
        for (var c = 0; c < 3; c++) {
          rgba[dst + c] =
              (255 * _unit(_near[i + c] + _far[i + c] * .55)).round();
        }
        rgba[dst + 3] = 255;
      }
    }
  }

  void _publish(double h, double blind, bool code, bool ping) {
    if (_busy) return;
    final stop = _hours.indexWhere((key) => key > h);
    final a = stop < 0 ? _hours.length - 2 : math.max(0, stop - 1);
    final blend = _unit((h - _hours[a]) / (_hours[a + 1] - _hours[a]));
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x, value = pixels[i];
        final material = value & 31, variant = value & 224;
        final col = variant == _day || variant == _warm
            ? 0
            : _columns[a +
                ((_bayer[(y & 3) * 4 + (x & 3)] + .5) / 16 < blend ? 1 : 0)];
        var level = ((material % 4) +
                (variant == _sun
                    ? 1
                    : variant == _shade
                        ? -1
                        : 0))
            .clamp(0, 3);
        var family = material ~/ 4;
        if (variant == _warm) {
          family = 4;
          level = math.max(2, level);
        } else if (family == 0 && col >= 2) {
          family = col == 3 ? 2 : 3;
          if (col == 2) level = math.max(0, level - 1);
        } else if (col > 0 && family == 1) {
          level = math.max(0, level - 1);
        }
        final color = _colors[family * 4 + level];
        rgba[i * 4] = color >> 16 & 255;
        rgba[i * 4 + 1] = color >> 8 & 255;
        rgba[i * 4 + 2] = color & 255;
        rgba[i * 4 + 3] = 255;
      }
    }
    _light(blind, code, ping);
    _busy = true;
    ui.decodeImageFromPixels(rgba, width, height + gh, ui.PixelFormat.rgba8888,
        (image) {
      _busy = false;
      if (_disposed) {
        image.dispose();
        return;
      }
      room?.dispose();
      room = image;
      repaint();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    room?.dispose();
    super.dispose();
  }
}

class _FocusPainter extends CustomPainter {
  _FocusPainter(this.scene, this.shader, this.dpr, this.height, this.showStage)
      : super(repaint: scene);

  final _FocusScene scene;
  final (ui.FragmentShader, ui.FragmentShader)? Function() shader;
  final double dpr, height;
  final bool showStage;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final cap = Rect.fromCenter(
        center: center, width: height * _width, height: height * _cap);
    final rim = cap.deflate(height * _rim);
    final outer = RRect.fromRectAndRadius(cap, Radius.circular(cap.height / 2));
    final inner = RRect.fromRectAndRadius(rim, Radius.circular(rim.height / 2));
    if (showStage) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = _stageColor(scene.night));
    }
    for (final (offset, blur, alpha) in [
      (.045, .055, .22),
      (.014, .017, .19)
    ]) {
      canvas.drawRRect(
          outer.shift(Offset(0, height * offset)),
          Paint()
            ..color = const Color(0xff16182f).withValues(alpha: alpha)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * blur));
    }
    final pixels = rim.height * dpr / 112;
    final k = pixels.floor();
    final scale = math.max(1, pixels / (k + 1) >= .88 ? k + 1 : k) / dpr;
    final origin = Offset(
      ((center.dx - 110 * scale) * dpr).round() / dpr,
      ((center.dy - 70 * scale) * dpr).round() / dpr,
    );
    final lamp =
        origin + Offset((scene.lampX + 14) * scale, (scene.lampY + 14) * scale);
    if (scene.lamp > 0) {
      _glow(canvas, lamp + Offset(0, rim.height * .32), rim.height * .84,
          const Color(0xffffb850), .29 * scene.lamp);
    }
    final housing =
        Color.lerp(Color(_colors[3]), Color(_colors[9]), scene.night)!;
    canvas.drawRRect(
        outer,
        Paint()
          ..shader = ui.Gradient.linear(
            cap.topLeft,
            cap.bottomRight,
            [
              Color.lerp(housing, Colors.white, .28)!,
              housing,
              Color.lerp(housing, const Color(0xff12152a), .23)!,
              Color.lerp(housing, Colors.white, .12)!,
            ],
            [0, .34, .74, 1],
          ));
    final image = scene.room;
    if (image == null) return;
    canvas.save();
    canvas.clipRRect(inner);
    canvas.drawRRect(
        inner, Paint()..color = Color(_colors[scene.night > .5 ? 10 : 2]));
    final imageRect =
        origin & Size(image.width * scale, _FocusScene.height * scale);
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), _FocusScene.height.toDouble());
    final pixelPaint = Paint()..filterQuality = FilterQuality.none;
    final glass = shader()?.$1;
    final lensShader = shader()?.$2;
    if (glass != null) {
      _drawShader(canvas, glass, image, origin, scale, rim, center, 0, 0);
    } else {
      canvas.drawImageRect(image, src, imageRect, pixelPaint);
      _glow(canvas, origin + Offset(53 * scale, 51 * scale), 40 * scale,
          const Color(0xff88c7ff), .14);
      if (scene.lamp > 0) {
        _glow(canvas, lamp, 37 * scale, const Color(0xffffa32b),
            .31 * scene.lamp);
      }
    }
    canvas.drawRRect(
        inner,
        Paint()
          ..shader = ui.Gradient.linear(
            rim.topCenter,
            rim.bottomCenter,
            [
              const Color(0x520c1124),
              Colors.transparent,
              const Color(0x330c1124)
            ],
            [0, .12, 1],
          ));
    canvas.drawRRect(
        inner.deflate(height * .002),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = height * .012
          ..color = const Color(0x35090f25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, height * .01));
    canvas.drawRRect(
        inner,
        Paint()
          ..shader = ui.Gradient.linear(
            rim.topLeft,
            rim.bottomRight,
            [Colors.transparent, const Color(0x12ffffff), Colors.transparent],
            [.12, .45, .72],
          ));
    final lens = center +
        Offset(_mix(-_travel, _travel, scene.x) * height,
            -.013 * scene.lift * height);
    final r = _radius * height * (1 + .012 * scene.lift);
    final rx = r * (1 + .20 * scene.stretch),
        ry = r * (1 - .075 * scene.stretch);
    final ellipse =
        Rect.fromCenter(center: lens, width: 2 * rx, height: 2 * ry);
    canvas.drawOval(
        ellipse.shift(Offset(0, height * (.02 + .022 * scene.lift))),
        Paint()
          ..color =
              const Color(0xff141831).withValues(alpha: .23 + .12 * scene.lift)
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, height * (.024 + .01 * scene.lift)));
    if (lensShader != null) {
      _drawShader(
          canvas, lensShader, image, origin, scale, ellipse, lens, rx, ry);
    } else {
      canvas.save();
      canvas.clipPath(Path()..addOval(ellipse));
      canvas.translate(lens.dx, lens.dy);
      canvas.scale(1.24);
      canvas.translate(-lens.dx, -lens.dy);
      canvas.drawImageRect(image, src, imageRect, pixelPaint);
      canvas.restore();
      canvas.drawOval(ellipse, Paint()..color = const Color(0x2cffffff));
    }
    canvas.restore();
  }

  void _drawShader(
      Canvas canvas,
      ui.FragmentShader shader,
      ui.Image image,
      Offset origin,
      double scale,
      Rect bounds,
      Offset center,
      double rx,
      double ry) {
    final args = [origin.dx, origin.dy, scale, center.dx, center.dy, rx, ry];
    for (var i = 0; i < args.length; i++) {
      shader.setFloat(i, args[i]);
    }
    shader.setImageSampler(0, image);
    canvas.drawRect(bounds, Paint()..shader = shader);
  }

  void _glow(
      Canvas canvas, Offset center, double radius, Color color, double alpha) {
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .26),
              color.withValues(alpha: 0)
            ],
            [0, .45, 1],
          ));
  }

  Color _stageColor(double t) {
    final l = _mix(.946, .17, t),
        a = _mix(.002, .006, t),
        b = _mix(.027, -.068, t);
    final ll = math.pow(l + .3963377774 * a + .2158037573 * b, 3);
    final mm = math.pow(l - .1055613458 * a - .0638541728 * b, 3);
    final ss = math.pow(l - .0894841775 * a - 1.291485548 * b, 3);
    int channel(num v) => (255 *
            _unit(v <= .0031308
                ? 12.92 * v
                : 1.055 * math.pow(v, 1 / 2.4) - .055))
        .round();
    return Color.fromARGB(
      255,
      channel(4.0767416621 * ll - 3.3077115913 * mm + .2309699292 * ss),
      channel(-1.2684380046 * ll + 2.6097574011 * mm - .3413193965 * ss),
      channel(-.0041960863 * ll - .7034186147 * mm + 1.707614701 * ss),
    );
  }

  @override
  bool shouldRepaint(covariant _FocusPainter oldDelegate) =>
      oldDelegate.dpr != dpr ||
      oldDelegate.height != height ||
      oldDelegate.showStage != showStage;
}
