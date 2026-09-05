#include "generated/default/fm2_init.h"

#include "fm2_app.h"
#include "content_status.h"

#include <cstdlib>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/filesystem/devices/stfs_container_device.h>
#include <rex/logging.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xam/content_manager.h>
#include <rex/system/xcontent.h>

REXCVAR_DEFINE_STRING(
    fm2_content_root, "", "Forza Motorsport 2",
    "Directory containing legally obtained FM2 marketplace packages");
REXCVAR_DEFINE_BOOL(fm2_auto_install_content, true, "Forza Motorsport 2",
                    "Install validated FM2 marketplace packages at startup");

namespace {

constexpr uint32_t kFm2TitleId = 0x4D5307EA;
constexpr std::string_view kContentDropDirectory = "content-packages";

std::string Hex8(uint32_t value) {
  std::ostringstream stream;
  stream << std::uppercase << std::hex << std::setw(8) << std::setfill('0')
         << value;
  return stream.str();
}

std::string EnvironmentRoot(const char* name) {
#ifdef _WIN32
  char* value = nullptr;
  size_t length = 0;
  if (_dupenv_s(&value, &length, name) != 0 || !value) {
    return {};
  }
  std::string root(value);
  std::free(value);
  return root;
#else
  const char* value = std::getenv(name);
  return value ? value : "";
#endif
}

std::filesystem::path InstalledContentPath(
    const std::filesystem::path& user_data_root,
    const std::filesystem::path& package_path) {
  return user_data_root / "0000000000000000" / Hex8(kFm2TitleId) /
         "00000002" / package_path.filename();
}

std::filesystem::path InstalledHeaderPath(
    const std::filesystem::path& user_data_root,
    const std::filesystem::path& package_path) {
  return user_data_root / "0000000000000000" / Hex8(kFm2TitleId) / "Headers" /
         "00000002" / (package_path.filename().string() + ".header");
}

fm2::ContentStatus InspectInstalled(const std::filesystem::path& user_data_root,
                                    const std::filesystem::path& package_path) {
  static_assert(sizeof(rex::system::xam::XCONTENT_AGGREGATE_DATA) == 328);
  return fm2::InspectContent(InstalledContentPath(user_data_root, package_path),
                             InstalledHeaderPath(user_data_root, package_path),
                             package_path.filename().string());
}

std::vector<std::filesystem::path> DiscoverSourceDirectories(
    const std::filesystem::path& app_root,
    const std::filesystem::path& user_data_root) {
  std::vector<std::filesystem::path> directories;
  auto add_directory = [&](std::filesystem::path directory) {
    if (directory.empty()) {
      return;
    }
    std::error_code ec;
    directory = std::filesystem::absolute(directory, ec);
    if (ec) {
      return;
    }
    for (const auto& existing : directories) {
      if (std::filesystem::equivalent(existing, directory, ec)) {
        return;
      }
      ec.clear();
    }
    directories.push_back(std::move(directory));
  };

  const std::string environment_root = EnvironmentRoot("FM2_CONTENT_ROOT");
  if (!environment_root.empty()) {
    add_directory(environment_root);
  }

  const std::string configured_root = REXCVAR_GET(fm2_content_root);
  if (!configured_root.empty()) {
    add_directory(configured_root);
  }
  add_directory(app_root / kContentDropDirectory);
  add_directory(user_data_root / kContentDropDirectory);
  return directories;
}

}  // namespace

void Fm2App::OnPostSetup() {
  if (!REXCVAR_GET(fm2_auto_install_content) || !runtime() ||
      !runtime()->kernel_state() ||
      !runtime()->kernel_state()->content_manager()) {
    return;
  }

  const uint32_t title_id = runtime()->kernel_state()->title_id();
  if (title_id != kFm2TitleId) {
    REXLOG_WARN("Skipping FM2 content install; running title ID is {:08X}",
                title_id);
    return;
  }

  const auto user_data_root = runtime()->user_data_root();
  const auto source_directories = DiscoverSourceDirectories(
      rex::filesystem::GetExecutableFolder(), user_data_root);
  std::unordered_set<std::string> seen_packages;
  size_t installed_count = 0;
  size_t existing_count = 0;
  size_t rejected_count = 0;

  for (const auto& source_directory : source_directories) {
    if (!std::filesystem::is_directory(source_directory)) {
      continue;
    }

    std::error_code iter_ec;
    std::filesystem::recursive_directory_iterator iterator(
        source_directory,
        std::filesystem::directory_options::skip_permission_denied, iter_ec);
    const std::filesystem::recursive_directory_iterator end;
    while (!iter_ec && iterator != end) {
      const auto entry = *iterator;
      iterator.increment(iter_ec);
      if (!entry.is_regular_file() || entry.path().has_extension()) {
        continue;
      }

      const auto package_path = entry.path();
      std::error_code canonical_ec;
      auto package_key =
          std::filesystem::weakly_canonical(package_path, canonical_ec).string();
      if (canonical_ec) {
        package_key = std::filesystem::absolute(package_path).string();
      }
      if (!seen_packages.insert(package_key).second) {
        continue;
      }

      const auto header =
          rex::filesystem::StfsContainerDevice::ReadPackageHeader(package_path);
      if (!header) {
        REXLOG_WARN("Rejecting FM2 content package with invalid STFS header: {}",
                    package_path.string());
        ++rejected_count;
        continue;
      }

      const auto content_type =
          static_cast<rex::system::XContentType>(header->metadata.content_type);
      const uint32_t package_title_id =
          header->metadata.execution_info.title_id;
      if (content_type != rex::system::XContentType::kMarketplaceContent ||
          package_title_id != kFm2TitleId) {
        REXLOG_WARN("Rejecting FM2 content package {} (type {:08X}, title {:08X})",
                    package_path.filename().string(),
                    static_cast<uint32_t>(content_type), package_title_id);
        ++rejected_count;
        continue;
      }

      const auto installed = InspectInstalled(user_data_root, package_path);
      if (installed.state == fm2::ContentState::kIncomplete) {
        REXLOG_WARN("FM2 content needs repair: {} ({}). Existing files preserved; no automatic overwrite.",
                    package_path.filename().string(), installed.reason);
        ++rejected_count;
        continue;
      }
      if (installed.state == fm2::ContentState::kPresent) {
        REXLOG_INFO("FM2 content files present: {} (stored license mask {:08X}; guest activation unverified)",
                    package_path.filename().string(), installed.license_mask);
        if (installed.license_mask == 0) {
          REXLOG_WARN("FM2 content has no stored license bits: {}. File presence does not establish car availability.",
                      package_path.filename().string());
        }
        ++existing_count;
        continue;
      }

      REXLOG_INFO("Installing FM2 content package: {}", package_path.string());
      const auto result =
          runtime()->kernel_state()->content_manager()->InstallContent(
              package_path);
      const auto after_install = InspectInstalled(user_data_root, package_path);
      if (result == 0 && after_install.state == fm2::ContentState::kPresent) {
        ++installed_count;
        REXLOG_INFO("Extracted FM2 content package: {} (stored license mask {:08X}; guest activation unverified)",
                    package_path.filename().string(), after_install.license_mask);
      } else {
        ++rejected_count;
        REXLOG_WARN("Failed to install FM2 content package {}: {:08X} ({})",
                    package_path.filename().string(),
                    static_cast<uint32_t>(result), after_install.reason);
      }
    }
    if (iter_ec) {
      REXLOG_WARN("Could not finish scanning FM2 content folder {}: {}",
                  source_directory.string(), iter_ec.message());
    }
  }

  REXLOG_INFO(
      "FM2 content file scan complete: {} extracted, {} present, {} rejected; guest activation not tested",
      installed_count, existing_count, rejected_count);
}
