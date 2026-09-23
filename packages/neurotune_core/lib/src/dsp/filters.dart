import 'dart:math';
import 'dart:typed_data';

class Complex {
  const Complex(this.real, this.imag);

  final double real;
  final double imag;

  Complex operator +(Complex other) => Complex(real + other.real, imag + other.imag);

  Complex operator -(Complex other) => Complex(real - other.real, imag - other.imag);

  Complex operator *(Complex other) =>
      Complex(real * other.real - imag * other.imag, real * other.imag + imag * other.real);

  Complex scale(double factor) => Complex(real * factor, imag * factor);

  Complex operator /(Complex other) {
    final denom = other.real * other.real + other.imag * other.imag;
    return Complex(
      (real * other.real + imag * other.imag) / denom,
      (imag * other.real - real * other.imag) / denom,
    );
  }

  double get abs => sqrt(real * real + imag * imag);

  Complex sqrtValue() {
    final radius = sqrt(abs);
    final angle = atan2(imag, real) / 2;
    return Complex(radius * cos(angle), radius * sin(angle));
  }
}

/// Direct-form II transposed SOS. Each section is `[b0, b1, b2, a0, a1, a2]`.
class SosFilter {
  SosFilter(this.sections)
      : _z1 = Float64List(sections.length),
        _z2 = Float64List(sections.length);

  final List<Float64List> sections;
  final Float64List _z1;
  final Float64List _z2;

  void reset() {
    _z1.fillRange(0, _z1.length, 0);
    _z2.fillRange(0, _z2.length, 0);
  }

  double process(double input) {
    var value = input;
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      final a0 = section[3];
      final b0 = section[0] / a0;
      final b1 = section[1] / a0;
      final b2 = section[2] / a0;
      final a1 = section[4] / a0;
      final a2 = section[5] / a0;
      final output = b0 * value + _z1[index];
      _z1[index] = b1 * value - a1 * output + _z2[index];
      _z2[index] = b2 * value - a2 * output;
      value = output;
    }
    return value;
  }

  Float64List processAll(List<double> input) {
    final output = Float64List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = process(input[i]);
    }
    return output;
  }
}

/// Butterworth bandpass. The transfer function matches SciPy `butter(..., output='sos')`.
List<Float64List> butterBandpassSos({
  required int order,
  required double lowHz,
  required double highHz,
  required double sampleRateHz,
}) {
  final nyquist = sampleRateHz / 2;
  const normalizedFs = 2.0;
  final warpedLow = 2 * normalizedFs * tan(pi * (lowHz / nyquist) / normalizedFs);
  final warpedHigh = 2 * normalizedFs * tan(pi * (highHz / nyquist) / normalizedFs);
  final center = sqrt(warpedLow * warpedHigh);
  final bandwidth = warpedHigh - warpedLow;
  final centerSquared = Complex(center * center, 0);

  final poles = <Complex>[];
  for (final pole in _butterPoles(order)) {
    final scaled = pole.scale(bandwidth / 2);
    final root = (scaled * scaled - centerSquared).sqrtValue();
    poles.add(scaled + root);
    poles.add(scaled - root);
  }

  const fs2 = Complex(4, 0);
  final digitalPoles = [for (final pole in poles) (fs2 + pole) / (fs2 - pole)];

  var numerator = const Complex(1, 0);
  var denominator = const Complex(1, 0);
  for (var i = 0; i < order; i++) {
    numerator = numerator * fs2;
  }
  for (final pole in poles) {
    denominator = denominator * (fs2 - pole);
  }
  final gain = (numerator / denominator).real * pow(bandwidth, order).toDouble();
  return _sections(digitalPoles, gain);
}

/// Second-order notch. Coefficients match SciPy `iirnotch`.
Float64List notchSos({
  required double notchHz,
  required double q,
  required double sampleRateHz,
}) {
  var frequency = 2 * notchHz / sampleRateHz;
  var bandwidth = frequency / q;
  bandwidth *= pi;
  frequency *= pi;
  final beta = tan(bandwidth / 2);
  final gain = 1 / (1 + beta);
  final cosine = cos(frequency);
  return Float64List.fromList([
    gain,
    gain * -2 * cosine,
    gain,
    1,
    -2 * gain * cosine,
    2 * gain - 1,
  ]);
}

List<Complex> _butterPoles(int order) {
  final poles = <Complex>[];
  for (var m = -order + 1; m < order; m += 2) {
    final angle = pi * m / (2 * order);
    poles.add(Complex(-cos(angle), -sin(angle)));
  }
  return poles;
}

List<Float64List> _sections(List<Complex> poles, double gain) {
  final remaining = [...poles];
  final sections = <Float64List>[];
  var first = true;
  while (remaining.isNotEmpty) {
    final pole = remaining.removeAt(0);
    final target = Complex(pole.real, -pole.imag);
    var partnerIndex = 0;
    var best = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final distance = (remaining[i] - target).abs;
      if (distance < best) {
        best = distance;
        partnerIndex = i;
      }
    }
    final partner = remaining.removeAt(partnerIndex);
    final sectionGain = first ? gain : 1.0;
    first = false;
    sections.add(
      Float64List.fromList([
        sectionGain,
        0,
        -sectionGain,
        1,
        -(pole.real + partner.real),
        (pole * partner).real,
      ]),
    );
  }
  return sections;
}
