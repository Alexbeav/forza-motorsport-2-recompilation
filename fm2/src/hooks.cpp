// Mid-asm hook implementations (game patches). Declarations are emitted
// automatically by codegen into the generated sources; definitions live here.

#include <rex/ppc.h>
#include <rex/cvar.h>
#include <rex/logging.h>
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

REXCVAR_DEFINE_BOOL(
    fm2_arcade_probe_logging, false, "Forza Motorsport 2/Diagnostics",
    "Log the high-frequency arcade-race localization probes")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

REXCVAR_DEFINE_BOOL(
    fm2_content_trace, false, "Forza Motorsport 2/Diagnostics",
    "Trace guest DLC enumeration, content opens, and mount results")
    .lifecycle(rex::cvar::Lifecycle::kHotReload);

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

uint32_t ReadGuestU32OrZero(uint32_t address) {
  return address == 0 ? 0 : ReadGuestU32(address);
}

bool IsPoisonU32(uint32_t value) {
  return value == 0xBEBEBEBE || value == 0xCDCDCDCD ||
         value == 0xDDDDDDDD || value == 0xFEEEFEEE;
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

void TraceFm2ContentEnumerationCreated(PPCRegister& r1, PPCRegister& r3) {
  if (!REXCVAR_GET(fm2_content_trace)) return;
  REXLOG_INFO("FM2_DLC_TRACE enumerator result={:08X} handle={:08X} buffer_size={}",
              r3.u32, ReadGuestU32(r1.u32 + 84), ReadGuestU32(r1.u32 + 88));
}

void TraceFm2ContentEnumerationCompleted(PPCRegister& r1, PPCRegister& r3) {
  if (!REXCVAR_GET(fm2_content_trace)) return;
  REXLOG_INFO("FM2_DLC_TRACE enumerate result={:08X} count={}",
              r3.u32, ReadGuestU32(r1.u32 + 80));
}

void TraceFm2ContentOpenResult(PPCRegister& r3, PPCRegister& r29) {
  if (!REXCVAR_GET(fm2_content_trace)) return;
  REXLOG_INFO("FM2_DLC_TRACE open index={} result={:08X}", r29.u32, r3.u32);
}

void TraceFm2ContentDescriptorResult(PPCRegister& r3, PPCRegister& r29) {
  if (!REXCVAR_GET(fm2_content_trace)) return;
  REXLOG_INFO("FM2_DLC_TRACE descriptor index={} result={:08X}", r29.u32, r3.u32);
}

void TraceFm2ContentMountResult(PPCRegister& r29, PPCRegister& r31) {
  if (!REXCVAR_GET(fm2_content_trace)) return;
  REXLOG_INFO("FM2_DLC_TRACE mount index={} result={:02X}", r29.u32, r31.u32 & 0xFF);
}

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
  if (IsPoisonU32(static_cast<uint32_t>(pending.cpu_context->lr)) ||
      IsPoisonU32(pending.cpu_context->r31.u32)) {
    REXLOG_ERROR(
        "[FM2_FIBER_POISON] target_context=0x{:08X} "
        "outgoing_context=0x{:08X} lr=0x{:08X} r31=0x{:08X} sp=0x{:08X}",
        pending.target_context, pending.outgoing_context,
        static_cast<uint32_t>(pending.cpu_context->lr),
        pending.cpu_context->r31.u32, pending.cpu_context->r1.u32);
  }
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

void ProbeArcadeRaceVirtualCall(PPCRegister& r11, PPCRegister& r28,
                                PPCRegister& r31) {
  if (!REXCVAR_GET(fm2_arcade_probe_logging)) {
    return;
  }
  REXLOG_ERROR(
      "[FM2_ARCADE_PROBE] call target=0x{:08X} receiver=0x{:08X} "
      "vtable=0x{:08X} inner=0x{:08X} state=0x{:08X}",
      r11.u32, r28.u32, ReadGuestU32(r28.u32),
      ReadGuestU32(r28.u32 + 12), r31.u32);
}

void ProbeArcadeRaceNestedCall(PPCRegister& r3, PPCRegister& r11) {
  if (!REXCVAR_GET(fm2_arcade_probe_logging)) {
    return;
  }
  REXLOG_ERROR(
      "[FM2_ARCADE_PROBE] nested target=0x{:08X} inner=0x{:08X} "
      "vtable=0x{:08X}",
      r11.u32, r3.u32, ReadGuestU32(r3.u32));
}

void ProbeArcadeObjectConstruct(PPCRegister& r3, PPCRegister& r4,
                                PPCRegister& r5) {
  if (!REXCVAR_GET(fm2_arcade_probe_logging)) {
    return;
  }
  const auto* context = ContextFromR3(r3);
  REXLOG_ERROR(
      "[FM2_ARCADE_PROBE] construct object=0x{:08X} inner_ref=0x{:08X} "
      "inner=0x{:08X} owner=0x{:08X} argument=0x{:08X} "
      "lr=0x{:08X} r31=0x{:08X} sp=0x{:08X}",
      r3.u32, r4.u32, ReadGuestU32(r4.u32), ReadGuestU32(r4.u32 + 4),
      r5.u32, static_cast<uint32_t>(context->lr), context->r31.u32,
      context->r1.u32);
}

void ProbeArcadeObjectConstructReturn(PPCRegister& r1, PPCRegister& r3) {
  const uint32_t saved_lr = ReadGuestU32OrZero(r1.u32 + 104);
  const uint32_t saved_r31 = ReadGuestU32OrZero(r1.u32 + 96);
  if (IsPoisonU32(saved_lr) || IsPoisonU32(saved_r31)) {
    REXLOG_ERROR(
        "[FM2_CONSTRUCT_RETURN_POISON] object=0x{:08X} sp=0x{:08X} "
        "saved_lr=0x{:08X} saved_r31=0x{:08X}",
        r3.u32, r1.u32, saved_lr, saved_r31);
  }
}

void GuardUnavailableFrontendService(PPCRegister& r3, PPCRegister& r11) {
  if (r11.u32 != 0 && ReadGuestU32(r3.u32 + 12) == 0) {
    r11.u64 = 0;
  }
}

void GuardUnavailableRaceServiceCleanup(PPCRegister& r11,
                                        PPCRegister& r31) {
  if (r11.u32 == 0) {
    return;
  }
  const uint32_t service = ReadGuestU32OrZero(r31.u32 + 12);
  const uint32_t backing_interface = ReadGuestU32OrZero(
      service == 0 ? 0 : service + 12);
  if (service != 0 && backing_interface == 0) {
    REXLOG_ERROR(
        "[FM2_RACE_GUARD] skipped unavailable race service cleanup "
        "owner=0x{:08X} service=0x{:08X}",
        r31.u32, service);
    r11.u64 = 0;
  }
}

void ProbeRaceLiveServiceInner(PPCRegister& r1, PPCRegister& r3,
                               PPCRegister& r4, PPCRegister& r11,
                               PPCRegister& r24) {
  const uint32_t inner_vtable = ReadGuestU32OrZero(r4.u32);
  if (r4.u32 == 0 || inner_vtable == 0) {
    const uint32_t receiver_vtable = ReadGuestU32OrZero(r24.u32);
    REXLOG_ERROR(
        "[FM2_RACE_PROBE] invalid inner object before 0x825401B4 "
        "sp=0x{:08X} destination=0x{:08X} wrapper=0x{:08X} "
        "inner=0x{:08X} inner_vtable=0x{:08X} retain=0x{:08X} "
        "receiver=0x{:08X} receiver_vtable=0x{:08X} query=0x{:08X} "
        "out=0x{:08X} old=0x{:08X}",
        r1.u32, r3.u32, r11.u32, r4.u32, inner_vtable,
        ReadGuestU32OrZero(inner_vtable == 0 ? 0 : inner_vtable + 4), r24.u32,
        receiver_vtable,
        ReadGuestU32OrZero(receiver_vtable == 0 ? 0 : receiver_vtable + 160),
        ReadGuestU32OrZero(r1.u32 + 88), ReadGuestU32OrZero(r1.u32 + 80));
  }
}
