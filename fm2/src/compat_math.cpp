#include <cmath>

// Clang's SIMDe lowering may emit C23 round-to-even libc calls. The Windows
// UCRT used by current LLVM releases does not provide those symbols yet.
#if defined(_WIN32)
namespace {
template <typename T>
T RoundToEven(T value) {
  if (!std::isfinite(value)) {
    return value;
  }

  const T lower = std::floor(value);
  const T fraction = value - lower;
  if (fraction < T{0.5}) {
    return lower;
  }
  if (fraction > T{0.5}) {
    return lower + T{1};
  }
  return std::fmod(lower, T{2}) == T{0} ? lower : lower + T{1};
}
}  // namespace

extern "C" float roundevenf(float value) { return RoundToEven(value); }
extern "C" double roundeven(double value) { return RoundToEven(value); }
#endif
