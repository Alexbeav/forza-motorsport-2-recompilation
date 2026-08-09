// Mid-asm hook implementations (game patches). Declarations are emitted
// automatically by codegen into the generated sources; definitions live here.

#include <rex/ppc.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xmemory.h>
#include <rex/system/xthread.h>
#include <rex/thread/fiber.h>

#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace {

constexpr uint32_t kKeSetCurrentStackPointers = 0x8294F2E8;
constexpr uint32_t kGuestFiberEntry = 0x82756580;
constexpr size_t kHostFiberStackSize = 1 << 20;

struct PendingSwitch {
  uint32_t outgoing_context;
  uint32_t target_context;
  PPCContext* cpu_context;
};

struct FiberStart {
  uint32_t guest_context;
  PPCContext* cpu_context;
  uint8_t* base;
};

thread_local std::unordered_map<uint32_t, rex::thread::Fiber*>
    g_host_fibers_by_guest_context;
thread_local std::unordered_map<rex::thread::Fiber*, PendingSwitch>
    g_pending_switches;
thread_local std::vector<std::unique_ptr<FiberStart>> g_fiber_starts;
thread_local rex::thread::Fiber* g_current_host_fiber = nullptr;

bool IsDeveloperSplashSkipEnabled() {
  char* raw_value = nullptr;
  size_t value_length = 0;
  if (_dupenv_s(&raw_value, &value_length, "FM2_SKIP_INTRO") != 0 ||
      raw_value == nullptr) {
    return false;
  }
  const std::unique_ptr<char, decltype(&std::free)> value(raw_value,
                                                          &std::free);
  const std::string_view setting(value.get());
  return setting == "1" || setting == "true" || setting == "TRUE" ||
         setting == "on" || setting == "ON";
}

PPCContext* ContextFromR3(PPCRegister& r3) {
  return reinterpret_cast<PPCContext*>(reinterpret_cast<std::byte*>(&r3) -
                                       offsetof(PPCContext, r3));
}

uint32_t ReadGuestU32(uint32_t address) {
  const auto* base = rex::system::kernel_state()->memory()->virtual_membase();
  uint32_t raw = 0;
  std::memcpy(&raw, base + address, sizeof(raw));
  return __builtin_bswap32(raw);
}

void RunGuestFiber(void* opaque) {
  const FiberStart start = *static_cast<FiberStart*>(opaque);
  // Fiber::Create retains the parameter until the first switch. Once entry is
  // running, the local copy is sufficient and the per-generation allocation
  // can be released instead of accumulating for the lifetime of the process.
  std::erase_if(g_fiber_starts, [opaque](const auto& candidate) {
    return candidate.get() == opaque;
  });
  g_host_fibers_by_guest_context[start.guest_context] = g_current_host_fiber;

  // The original guest switch tail-calls this kernel routine before returning
  // through the target context's restored LR. A newly created host fiber has
  // no suspended generated frame to perform that tail call, so do both steps
  // explicitly on first entry.
  auto* set_stack =
      rex::runtime::ResolveIndirectFunction(kKeSetCurrentStackPointers);
  set_stack(*start.cpu_context, start.base);
  auto* resume = rex::runtime::ResolveIndirectFunction(
      static_cast<uint32_t>(start.cpu_context->lr));
  resume(*start.cpu_context, start.base);
}

}  // namespace

void CaptureGuestFiberSwitch(PPCRegister& r3, PPCRegister& r5) {
  if (g_current_host_fiber == nullptr) {
    auto* thread = rex::system::XThread::GetCurrentThread();
    if (thread == nullptr) {
      return;
    }
    g_current_host_fiber = thread->main_fiber();
  }
  g_pending_switches[g_current_host_fiber] = {
      .outgoing_context = r5.u32,
      .target_context = r3.u32,
      .cpu_context = ContextFromR3(r3),
  };
}

void CommitGuestFiberSwitch(PPCRegister& r3) {
  auto* current = g_current_host_fiber;
  const auto pending_it = g_pending_switches.find(current);
  if (current == nullptr || pending_it == g_pending_switches.end()) {
    return;
  }

  const PendingSwitch pending = pending_it->second;
  g_host_fibers_by_guest_context[pending.outgoing_context] = current;
  if (pending.target_context == pending.outgoing_context) {
    return;
  }

  rex::thread::Fiber* target = nullptr;
  auto target_it =
      g_host_fibers_by_guest_context.find(pending.target_context);
  // FM2 reuses guest context storage for successive jobs. A context reset to
  // its initial exit thunk is a new execution generation, even when its guest
  // address is unchanged. Resuming the old suspended host stack while loading
  // that reset register image mixes two generations and corrupts nonvolatile
  // state. Retire the old host fiber and start the reset context afresh.
  const uint32_t target_lr = ReadGuestU32(pending.target_context + 28);
  if (target_it != g_host_fibers_by_guest_context.end() &&
      target_it->second != current && target_lr == kGuestFiberEntry) {
    g_pending_switches.erase(target_it->second);
    target_it->second->Destroy();
    g_host_fibers_by_guest_context.erase(target_it);
    target_it = g_host_fibers_by_guest_context.end();
  }
  if (target_it != g_host_fibers_by_guest_context.end()) {
    target = target_it->second;
  } else {
    auto start = std::make_unique<FiberStart>();
    start->guest_context = pending.target_context;
    start->cpu_context = pending.cpu_context;
    start->base = rex::system::kernel_state()->memory()->virtual_membase();
    target = rex::thread::Fiber::Create(kHostFiberStackSize, RunGuestFiber,
                                        start.get());
    g_host_fibers_by_guest_context[pending.target_context] = target;
    g_fiber_starts.push_back(std::move(start));
  }

  g_current_host_fiber = target;
  rex::thread::Fiber::SwitchTo(target);
  g_current_host_fiber = current;
}

void ApplyDeveloperSplashSkipAtStartup(PPCRegister& r11) {
  if (IsDeveloperSplashSkipEnabled()) {
    r11.u64 = 1;
  }
}

void ApplyDeveloperSplashSkipAtCleanup(PPCRegister& r11) {
  if (IsDeveloperSplashSkipEnabled()) {
    r11.u64 = 1;
  }
}
