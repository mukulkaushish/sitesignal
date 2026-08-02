import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    _writeSound(arguments.single, duration: 0.78, waveform: _classic);
    return;
  }
  _writeSoundPair('site_signal_alert.wav', duration: 0.78, waveform: _classic);
  _writeSoundPair(
    'site_signal_bright_chime.wav',
    duration: 0.82,
    waveform: _brightChime,
  );
  _writeSoundPair(
    'site_signal_soft_pulse.wav',
    duration: 0.9,
    waveform: _softPulse,
  );
  _writeSoundPair('site_signal_beacon.wav', duration: 0.94, waveform: _beacon);
}

void _writeSoundPair(
  String fileName, {
  required double duration,
  required double Function(double time) waveform,
}) {
  _writeSound('assets/$fileName', duration: duration, waveform: waveform);
  _writeSound(
    'android/app/src/main/res/raw/$fileName',
    duration: duration,
    waveform: waveform,
  );
}

void _writeSound(
  String outputPath, {
  required double duration,
  required double Function(double time) waveform,
}) {
  final sampleCount = (_sampleRate * duration).round();
  final samples = Int16List(sampleCount);

  for (var index = 0; index < sampleCount; index++) {
    final time = index / _sampleRate;
    final signal = waveform(time);
    samples[index] = (signal.clamp(-0.92, 0.92) * 32767).round();
  }

  final wav = ByteData(44 + samples.lengthInBytes);
  _writeAscii(wav, 0, 'RIFF');
  wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
  _writeAscii(wav, 8, 'WAVE');
  _writeAscii(wav, 12, 'fmt ');
  wav.setUint32(16, 16, Endian.little);
  wav.setUint16(20, 1, Endian.little);
  wav.setUint16(22, 1, Endian.little);
  wav.setUint32(24, _sampleRate, Endian.little);
  wav.setUint32(28, _sampleRate * 2, Endian.little);
  wav.setUint16(32, 2, Endian.little);
  wav.setUint16(34, 16, Endian.little);
  _writeAscii(wav, 36, 'data');
  wav.setUint32(40, samples.lengthInBytes, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    wav.setInt16(44 + (index * 2), samples[index], Endian.little);
  }

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(wav.buffer.asUint8List(), flush: true);
  stdout.writeln('Wrote ${output.path} (${wav.lengthInBytes} bytes)');
}

double _classic(double time) {
  return _bell(time, start: 0, duration: 0.46, frequency: 659.255, gain: 0.52) +
      _bell(time, start: 0.2, duration: 0.58, frequency: 987.767, gain: 0.42);
}

double _brightChime(double time) {
  return _bell(time, start: 0, duration: 0.42, frequency: 783.991, gain: 0.42) +
      _bell(time, start: 0.14, duration: 0.46, frequency: 987.767, gain: 0.38) +
      _bell(time, start: 0.3, duration: 0.5, frequency: 1318.51, gain: 0.34);
}

double _softPulse(double time) {
  return _bell(time, start: 0, duration: 0.68, frequency: 440, gain: 0.34) +
      _bell(time, start: 0.18, duration: 0.7, frequency: 554.365, gain: 0.25);
}

double _beacon(double time) {
  return _bell(time, start: 0, duration: 0.24, frequency: 739.989, gain: 0.44) +
      _bell(time, start: 0.34, duration: 0.24, frequency: 739.989, gain: 0.4) +
      _bell(time, start: 0.68, duration: 0.24, frequency: 987.767, gain: 0.4);
}

double _bell(
  double time, {
  required double start,
  required double duration,
  required double frequency,
  required double gain,
}) {
  final localTime = time - start;
  if (localTime < 0 || localTime >= duration) {
    return 0;
  }
  final attack = (localTime / 0.012).clamp(0.0, 1.0);
  final release = math.pow(1 - (localTime / duration), 2.6).toDouble();
  final phase = 2 * math.pi * frequency * localTime;
  final timbre = math.sin(phase) + (0.18 * math.sin(phase * 2));
  return timbre * attack * release * gain;
}

void _writeAscii(ByteData data, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    data.setUint8(offset + index, value.codeUnitAt(index));
  }
}
