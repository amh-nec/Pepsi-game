import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Tiny software synth: every sound effect is generated as raw PCM at start-up
/// and handed to audioplayers as an in-memory WAV, so the game ships with no
/// audio assets at all.
class GameAudio {
  static const int _sampleRate = 22050;

  final AudioPlayer _pour = AudioPlayer(playerId: 'pour');
  final AudioPlayer _fizz = AudioPlayer(playerId: 'fizz');
  final AudioPlayer _oneShot = AudioPlayer(playerId: 'oneshot');

  late final Uint8List _pourWav;
  late final Uint8List _fizzWav;
  late final Uint8List _successWav;
  late final Uint8List _failWav;

  bool _ready = false;
  bool _pouring = false;
  bool muted = false;

  Future<void> init() async {
    try {
      _pourWav = _wav(_pourSamples());
      _fizzWav = _wav(_fizzSamples());
      _successWav = _wav(_successSamples());
      _failWav = _wav(_failSamples());
      for (final p in [_pour, _fizz, _oneShot]) {
        await p.setReleaseMode(
          p == _oneShot ? ReleaseMode.stop : ReleaseMode.loop,
        );
        await p.setPlayerMode(PlayerMode.lowLatency);
      }
      _ready = true;
    } catch (e) {
      debugPrint('GameAudio disabled: $e');
      _ready = false;
    }
  }

  Future<void> setPouring(bool on, {double intensity = 1}) async {
    if (!_ready || muted) return;
    try {
      if (on && !_pouring) {
        _pouring = true;
        await _pour.play(BytesSource(_pourWav), volume: 0.25 + 0.5 * intensity);
        await _fizz.play(BytesSource(_fizzWav), volume: 0.18);
      } else if (!on && _pouring) {
        _pouring = false;
        await _pour.stop();
        await _fizz.stop();
      } else if (on) {
        await _pour.setVolume(0.25 + 0.5 * intensity);
      }
    } catch (_) {/* audio is a nicety, never a crash */}
  }

  Future<void> success() => _play(_successWav, 0.8);
  Future<void> fail() => _play(_failWav, 0.8);

  Future<void> _play(Uint8List wav, double volume) async {
    if (!_ready || muted) return;
    try {
      await _oneShot.stop();
      await _oneShot.play(BytesSource(wav), volume: volume);
    } catch (_) {}
  }

  Future<void> stopAll() async {
    _pouring = false;
    if (!_ready) return;
    try {
      await _pour.stop();
      await _fizz.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final p in [_pour, _fizz, _oneShot]) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  // ---- Synthesis ----------------------------------------------------------

  /// Band-limited noise with a slow amplitude wobble: reads as splashing
  /// liquid when looped.
  Float64List _pourSamples() {
    const seconds = 1.0;
    final n = (_sampleRate * seconds).round();
    final out = Float64List(n);
    final rng = math.Random(1234);
    double lp = 0, hp = 0, prev = 0;
    for (int i = 0; i < n; i++) {
      final white = rng.nextDouble() * 2 - 1;
      lp += (white - lp) * 0.35; // low pass -> body
      hp = 0.85 * (hp + lp - prev); // high pass -> hiss
      prev = lp;
      final t = i / _sampleRate;
      final wobble = 0.75 + 0.25 * math.sin(2 * math.pi * 3.1 * t);
      out[i] = (lp * 0.7 + hp * 0.5) * wobble * 0.6;
    }
    _crossfadeLoop(out, 400);
    return out;
  }

  /// Sparse clicks: the crackle of a fresh head of foam.
  Float64List _fizzSamples() {
    const seconds = 1.5;
    final n = (_sampleRate * seconds).round();
    final out = Float64List(n);
    final rng = math.Random(99);
    for (int i = 0; i < n; i++) {
      if (rng.nextDouble() < 0.004) {
        final len = 40 + rng.nextInt(90);
        final f = 1800 + rng.nextDouble() * 4200;
        final amp = 0.15 + rng.nextDouble() * 0.35;
        for (int k = 0; k < len && i + k < n; k++) {
          final env = math.exp(-k / (len * 0.28));
          out[i + k] += math.sin(2 * math.pi * f * k / _sampleRate) * env * amp;
        }
      }
    }
    _crossfadeLoop(out, 600);
    return out;
  }

  /// Bright major arpeggio.
  Float64List _successSamples() =>
      _melody(const [523.25, 659.25, 783.99, 1046.5], 0.16, 0.55);

  /// Descending detuned buzz.
  Float64List _failSamples() =>
      _melody(const [220.0, 174.6, 130.8], 0.22, 0.6, square: true);

  Float64List _melody(
    List<double> freqs,
    double noteLen,
    double amp, {
    bool square = false,
  }) {
    final total = (_sampleRate * (noteLen * freqs.length + 0.35)).round();
    final out = Float64List(total);
    for (int nIdx = 0; nIdx < freqs.length; nIdx++) {
      final start = (nIdx * noteLen * _sampleRate).round();
      final len = (noteLen * 2.0 * _sampleRate).round();
      for (int k = 0; k < len && start + k < total; k++) {
        final t = k / _sampleRate;
        final env = math.exp(-t * (square ? 6 : 4.5));
        var s = math.sin(2 * math.pi * freqs[nIdx] * t);
        if (square) s = s.sign * 0.6 + 0.4 * math.sin(4 * math.pi * freqs[nIdx] * t);
        out[start + k] += s * env * amp;
      }
    }
    return out;
  }

  static void _crossfadeLoop(Float64List buf, int fade) {
    final n = buf.length;
    if (fade * 2 >= n) return;
    for (int i = 0; i < fade; i++) {
      final t = i / fade;
      buf[i] = buf[i] * t + buf[n - fade + i] * (1 - t);
    }
  }

  /// Wraps mono float samples in a 16-bit PCM WAV container.
  static Uint8List _wav(Float64List samples) {
    const bitsPerSample = 16;
    const channels = 1;
    final dataLen = samples.length * 2;
    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(channels);
    u32(_sampleRate);
    u32(_sampleRate * channels * bitsPerSample ~/ 8);
    u16(channels * bitsPerSample ~/ 8);
    u16(bitsPerSample);
    str('data');
    u32(dataLen);

    final pcm = Uint8List(dataLen);
    final view = pcm.buffer.asByteData();
    for (int i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      view.setInt16(i * 2, v, Endian.little);
    }
    bytes.add(pcm);
    return bytes.toBytes();
  }
}
