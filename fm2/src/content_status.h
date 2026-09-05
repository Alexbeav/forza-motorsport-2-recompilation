#pragma once

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>

namespace fm2 {

enum class ContentState { kAbsent, kPresent, kIncomplete };

struct ContentStatus {
  ContentState state = ContentState::kIncomplete;
  uint32_t license_mask = 0;
  std::string reason;
};

// The pinned Windows SDK stores XCONTENT_AGGREGATE_DATA (328 bytes), followed
// by an optional native little-endian license mask. This is a structural
// inspection only: it does not establish package authenticity or activation.
inline ContentStatus InspectContent(const std::filesystem::path& directory,
                                    const std::filesystem::path& header,
                                    std::string_view package_name) {
  namespace fs = std::filesystem;
  std::error_code ec;
  const bool has_directory = fs::exists(directory, ec);
  if (ec) return {ContentState::kIncomplete, 0, "cannot inspect content path"};
  const bool has_header = fs::exists(header, ec);
  if (ec) return {ContentState::kIncomplete, 0, "cannot inspect header path"};
  if (!has_directory && !has_header) return {ContentState::kAbsent, 0, {}};
  if (!fs::is_directory(directory, ec) || ec || !fs::is_regular_file(header, ec) || ec) {
    return {ContentState::kIncomplete, 0, "content directory or header is missing"};
  }
  const auto size = fs::file_size(header, ec);
  if (ec || (size != 328 && size != 332)) {
    return {ContentState::kIncomplete, 0, "unexpected installed header size"};
  }
  std::array<unsigned char, 332> bytes{};
  std::ifstream input(header, std::ios::binary);
  if (!input.read(reinterpret_cast<char*>(bytes.data()), size)) {
    return {ContentState::kIncomplete, 0, "cannot read installed header"};
  }
  auto be32 = [&](size_t offset) {
    return (uint32_t(bytes[offset]) << 24) | (uint32_t(bytes[offset + 1]) << 16) |
           (uint32_t(bytes[offset + 2]) << 8) | uint32_t(bytes[offset + 3]);
  };
  const std::string_view name(reinterpret_cast<const char*>(bytes.data() + 264), 42);
  const auto end = name.find('\0');
  if (be32(4) != 2 || be32(320) != 0x4D5307EA || name.substr(0, end) != package_name) {
    return {ContentState::kIncomplete, 0, "installed header identity does not match FM2 package"};
  }
  const uint32_t mask = uint32_t(bytes[328]) | (uint32_t(bytes[329]) << 8) |
                        (uint32_t(bytes[330]) << 16) | (uint32_t(bytes[331]) << 24);
  fs::recursive_directory_iterator it(directory, fs::directory_options::none, ec), end_it;
  bool has_payload = false;
  while (!ec && it != end_it) {
    if (it->is_regular_file(ec) && !ec && it->file_size(ec) > 0 && !ec) has_payload = true;
    if (ec) break;
    it.increment(ec);
  }
  if (ec || !has_payload) {
    return {ContentState::kIncomplete, mask, "content is empty or unreadable"};
  }
  return {ContentState::kPresent, mask, {}};
}

}  // namespace fm2
