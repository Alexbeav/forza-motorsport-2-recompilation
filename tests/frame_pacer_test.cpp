#include "frame_pacer.h"

#include <cstdlib>
#include <iostream>
#include <fstream>
#include <thread>
#include <source_location>

#ifdef _WIN32
#include <windows.h>
#include <rex/cvar.h>
namespace rex::thread {
void Sleep(std::chrono::microseconds);
}
#endif

using rex::graphics::FramePacer;
using namespace std::chrono_literals;

void Check(bool value, std::source_location location = std::source_location::current()) {
  if (!value) { std::cerr << "Check failed at line " << location.line() << '\n'; std::exit(1); }
}

int main(int argc, char** argv) {
#ifdef _WIN32
  rex::cvar::Init(argc, argv);
  const auto guest_refresh = rex::cvar::GetFlagByName("video_mode_refresh_rate");
  std::ofstream("frame-pacer-config.toml") << "gpu_max_fps = 37\n";
  rex::cvar::LoadConfig("frame-pacer-config.toml");
  Check(LoadLibraryW(L"rexgpu-xenos.dll") != nullptr);
  std::cout << "Loaded cap: " << rex::cvar::GetFlagByName("gpu_max_fps") << '\n';
  Check(rex::cvar::GetFlagByName("gpu_max_fps") == "37");
  Check(!rex::cvar::SetFlagByName("gpu_max_fps", "1001"));
  Check(rex::cvar::SetFlagByName("gpu_max_fps", "0"));
  Check(rex::cvar::GetFlagByName("video_mode_refresh_rate") == guest_refresh);
  std::cout << "GPU plugin consumed deferred TOML cap; guest refresh unchanged.\n";
#endif
  FramePacer pacer;
  FramePacer::Clock::time_point tick{};
  int sleeps = 0;
  auto now = [&] { return tick; };
  auto sleep = [&](auto duration) { ++sleeps; tick += duration; };
  pacer.Wait(0, now, sleep);
  pacer.Wait(60, now, sleep);
  Check(sleeps == 0);
  pacer.Wait(60, now, sleep);
  Check(tick >= FramePacer::Clock::time_point{} + 1s / 60.0 && sleeps == 1);
  tick += 100ms;
  const auto late = tick;
  pacer.Wait(60, now, sleep);
  Check(tick == late && sleeps == 1);
  pacer.Wait(60, now, sleep);
  Check(tick >= late + 1s / 60.0 && sleeps == 2);
  pacer.Wait(30, now, sleep);
  const auto changed = tick;
  pacer.Wait(30, now, sleep);
  Check(tick >= changed + 1s / 30.0);
  pacer.Wait(0, now, sleep);
  const auto disabled = tick;
  pacer.Wait(0, now, sleep);
  Check(tick == disabled);
  pacer.Wait(120, now, sleep);
  int early_wakes = 0;
  pacer.Wait(120, now, [&](auto duration) {
    ++early_wakes;
    tick += early_wakes == 1 ? duration / 2 : duration;
  });
  Check(early_wakes == 2 && tick >= disabled + 1s / 120.0);

#ifdef _WIN32
  // Exercise the same timer implementation used by the production GPU plugin.
  auto host_sleep = [](auto duration) { rex::thread::Sleep(duration); };
#else
  auto host_sleep = [](auto duration) { std::this_thread::sleep_for(duration); };
#endif
  for (int fps : {30, 60, 120}) {
    FramePacer real;
    auto clock = [] { return FramePacer::Clock::now(); };
    real.Wait(fps, clock, host_sleep);
    auto previous = clock();
    const auto start = previous;
    for (int i = 0; i < fps / 2; ++i) {
      real.Wait(fps, clock, host_sleep);
      const auto current = clock();
      // The previous timestamp follows Wait, so allow 100us of measurement overhead.
      Check(current - previous >= 1s / double(fps) - 100us);
      previous = current;
    }
    const double measured = (fps / 2) / std::chrono::duration<double>(previous - start).count();
    Check(measured <= fps * 1.01 && measured >= fps * 0.75);
    std::cout << fps << " fps cap: " << measured << " swaps/s\n";
  }
  std::cout << "Frame pacing checks passed. No game launched.\n";
}
