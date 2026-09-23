import 'dart:math';
import 'dart:typed_data';

/// In-place radix-2 FFT. The sign matches NumPy's forward transform.
void fft(Float64List real, Float64List imag) {
  final n = real.length;
  if (n != imag.length || n == 0 || (n & (n - 1)) != 0) {
    throw ArgumentError('FFT length must be a power of two');
  }
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    while (j & bit != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      final swapReal = real[i];
      real[i] = real[j];
      real[j] = swapReal;
      final swapImag = imag[i];
      imag[i] = imag[j];
      imag[j] = swapImag;
    }
  }
  for (var length = 2; length <= n; length <<= 1) {
    final angle = -2 * pi / length;
    final wlenReal = cos(angle);
    final wlenImag = sin(angle);
    for (var start = 0; start < n; start += length) {
      var wReal = 1.0;
      var wImag = 0.0;
      final half = length >> 1;
      for (var k = 0; k < half; k++) {
        final oddReal = real[start + k + half];
        final oddImag = imag[start + k + half];
        final vReal = oddReal * wReal - oddImag * wImag;
        final vImag = oddReal * wImag + oddImag * wReal;
        final uReal = real[start + k];
        final uImag = imag[start + k];
        real[start + k] = uReal + vReal;
        imag[start + k] = uImag + vImag;
        real[start + k + half] = uReal - vReal;
        imag[start + k + half] = uImag - vImag;
        final nextReal = wReal * wlenReal - wImag * wlenImag;
        wImag = wReal * wlenImag + wImag * wlenReal;
        wReal = nextReal;
      }
    }
  }
}

/// One-sided real FFT, bins `0 .. n/2` inclusive.
({Float64List real, Float64List imag}) rfft(List<double> input) {
  final n = input.length;
  if (n > 0 && (n & (n - 1)) == 0) {
    final real = Float64List.fromList(input);
    final imag = Float64List(n);
    fft(real, imag);
    final bins = n ~/ 2 + 1;
    return (
      real: Float64List.sublistView(real, 0, bins),
      imag: Float64List.sublistView(imag, 0, bins),
    );
  }
  final bins = n ~/ 2 + 1;
  final real = Float64List(bins);
  final imag = Float64List(bins);
  for (var k = 0; k < bins; k++) {
    var sumReal = 0.0;
    var sumImag = 0.0;
    for (var t = 0; t < n; t++) {
      final angle = -2 * pi * k * t / n;
      sumReal += input[t] * cos(angle);
      sumImag += input[t] * sin(angle);
    }
    real[k] = sumReal;
    imag[k] = sumImag;
  }
  return (real: real, imag: imag);
}
