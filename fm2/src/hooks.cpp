// Mid-asm hook implementations (game patches). Declarations are emitted
// automatically by codegen into the generated sources; definitions live here.

#include <rex/ppc.h>
#include <rex/logging.h>

// The blocking read call in sub_8243C8D0 comes back with ctx->r31 zeroed
// (suspected runtime APC/callback nonvolatile clobber). Preserve r31 across
// the call; the guard below catches any path the pair does not cover.
static thread_local uint32_t g_saved_r31;

void SaveR31BeforeRead(PPCRegister& r31) {
  g_saved_r31 = r31.u32;
}

void RestoreR31AfterRead(PPCRegister& r31) {
  if (r31.u32 != g_saved_r31) {
    REXLOG_WARN("[hook] r31 clobbered across read call: {:08X} -> {:08X}, restoring",
                g_saved_r31, r31.u32);
    r31.u32 = g_saved_r31;
  }
}

bool GuardStreamReadNull(PPCRegister& r31) {
  if (r31.u32 == 0) {
    REXLOG_WARN("[hook] GuardStreamReadNull: null stream in sub_8243C8D0, skipping read");
    return true;
  }
  return false;
}
