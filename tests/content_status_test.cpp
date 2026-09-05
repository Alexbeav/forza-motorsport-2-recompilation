#include "content_status.h"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
  if (argc == 4) {
    const auto result = fm2::InspectContent(argv[1], argv[2], argv[3]);
    std::cout << "state=" << static_cast<int>(result.state)
              << " mask=" << result.license_mask << " reason=" << result.reason << '\n';
    return result.state == fm2::ContentState::kPresent ? 0 : 1;
  }
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() /
      ("fm2-content-test-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  const auto data = root / "data";
  const auto header = root / "test.header";
  const std::string name(42, 'A');
  fs::create_directories(root);
  int cases = 0;
  auto expect = [&](fm2::ContentState state, uint32_t mask = 0) {
    const auto result = fm2::InspectContent(data, header, name);
    if (result.state != state || result.license_mask != mask) {
      throw std::runtime_error("Unexpected content status: " + result.reason);
    }
    ++cases;
  };
  std::array<unsigned char, 332> bytes{};
  auto write = [&](size_t size) {
    std::ofstream out(header, std::ios::binary | std::ios::trunc);
    out.write(reinterpret_cast<const char*>(bytes.data()), size);
  };
  expect(fm2::ContentState::kAbsent);
  fs::create_directory(data);
  expect(fm2::ContentState::kIncomplete);
  write(4);
  expect(fm2::ContentState::kIncomplete);
  bytes[7] = 2;
  bytes[320] = 0x4D; bytes[321] = 0x53; bytes[322] = 0x07; bytes[323] = 0xEA;
  std::copy(name.begin(), name.end(), bytes.begin() + 264);
  write(328);
  expect(fm2::ContentState::kIncomplete);  // Empty content must not count as installed.
  std::ofstream(data / "payload.txt") << "Synthetic test data";
  expect(fm2::ContentState::kPresent);
  bytes[328] = 1;
  write(332);
  expect(fm2::ContentState::kPresent, 1);
  bytes[328] = 0; bytes[329] = 2;
  write(332);
  expect(fm2::ContentState::kPresent, 512);
  bytes[323] = 0;
  write(332);
  expect(fm2::ContentState::kIncomplete);
  bytes[323] = 0xEA; bytes[7] = 1;
  write(332);
  expect(fm2::ContentState::kIncomplete);
  bytes[7] = 2; bytes[264] = 'B';
  write(332);
  expect(fm2::ContentState::kIncomplete);
  std::cout << cases << " content status cases passed. Fixtures: " << root << '\n';
}
