// Mid-asm hook implementations (game patches). Declarations are emitted
// automatically by codegen into the generated sources; definitions live here.

#include <rex/ppc.h>

#include <array>

namespace {

constexpr size_t kSavedRegisterCount = 37;
thread_local std::array<PPCRegister, kSavedRegisterCount> g_saved_switch_registers;
thread_local std::array<PPCVRegister, 12> g_saved_switch_vectors;
thread_local std::array<PPCCRRegister, 3> g_saved_switch_cr;
thread_local bool g_saved_switch_active = false;

template <typename... Registers>
void SaveRegisters(Registers&... registers) {
  size_t index = 0;
  ((g_saved_switch_registers[index++] = registers), ...);
}

template <typename... Registers>
void RestoreRegisters(Registers&... registers) {
  size_t index = 0;
  ((registers = g_saved_switch_registers[index++]), ...);
}

template <typename... Registers>
void SaveVectors(Registers&... registers) {
  size_t index = 0;
  ((g_saved_switch_vectors[index++] = registers), ...);
}

template <typename... Registers>
void RestoreVectors(Registers&... registers) {
  size_t index = 0;
  ((registers = g_saved_switch_vectors[index++]), ...);
}

}  // namespace

void SaveContextSwitchCaller(
    PPCRegister& r1, PPCRegister& r14, PPCRegister& r15, PPCRegister& r16,
    PPCRegister& r17, PPCRegister& r18, PPCRegister& r19, PPCRegister& r20,
    PPCRegister& r21, PPCRegister& r22, PPCRegister& r23, PPCRegister& r24,
    PPCRegister& r25, PPCRegister& r26, PPCRegister& r27, PPCRegister& r28,
    PPCRegister& r29, PPCRegister& r30, PPCRegister& r31,
    PPCCRRegister& cr2, PPCCRRegister& cr3, PPCCRRegister& cr4,
    PPCRegister& f14, PPCRegister& f15, PPCRegister& f16, PPCRegister& f17,
    PPCRegister& f18, PPCRegister& f19, PPCRegister& f20, PPCRegister& f21,
    PPCRegister& f22, PPCRegister& f23, PPCRegister& f24, PPCRegister& f25,
    PPCRegister& f26, PPCRegister& f27, PPCRegister& f28, PPCRegister& f29,
    PPCRegister& f30, PPCRegister& f31,
    PPCVRegister& v20, PPCVRegister& v21, PPCVRegister& v22, PPCVRegister& v23,
    PPCVRegister& v24, PPCVRegister& v25, PPCVRegister& v26, PPCVRegister& v27,
    PPCVRegister& v28, PPCVRegister& v29, PPCVRegister& v30, PPCVRegister& v31) {
  SaveRegisters(r1, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23, r24,
                r25, r26, r27, r28, r29, r30, r31, f14, f15, f16, f17, f18,
                f19, f20, f21, f22, f23, f24, f25, f26, f27, f28, f29, f30,
                f31);
  SaveVectors(v20, v21, v22, v23, v24, v25, v26, v27, v28, v29, v30, v31);
  g_saved_switch_cr = {cr2, cr3, cr4};
  g_saved_switch_active = true;
}

void RestoreContextSwitchCaller(
    PPCRegister& r1, PPCRegister& r14, PPCRegister& r15, PPCRegister& r16,
    PPCRegister& r17, PPCRegister& r18, PPCRegister& r19, PPCRegister& r20,
    PPCRegister& r21, PPCRegister& r22, PPCRegister& r23, PPCRegister& r24,
    PPCRegister& r25, PPCRegister& r26, PPCRegister& r27, PPCRegister& r28,
    PPCRegister& r29, PPCRegister& r30, PPCRegister& r31,
    PPCCRRegister& cr2, PPCCRRegister& cr3, PPCCRRegister& cr4,
    PPCRegister& f14, PPCRegister& f15, PPCRegister& f16, PPCRegister& f17,
    PPCRegister& f18, PPCRegister& f19, PPCRegister& f20, PPCRegister& f21,
    PPCRegister& f22, PPCRegister& f23, PPCRegister& f24, PPCRegister& f25,
    PPCRegister& f26, PPCRegister& f27, PPCRegister& f28, PPCRegister& f29,
    PPCRegister& f30, PPCRegister& f31,
    PPCVRegister& v20, PPCVRegister& v21, PPCVRegister& v22, PPCVRegister& v23,
    PPCVRegister& v24, PPCVRegister& v25, PPCVRegister& v26, PPCVRegister& v27,
    PPCVRegister& v28, PPCVRegister& v29, PPCVRegister& v30, PPCVRegister& v31) {
  // 0x82453114 is also the branch target when the switch pointer is null.
  // In that path SaveContextSwitchCaller was not executed and there is
  // intentionally nothing to restore.
  if (!g_saved_switch_active) {
    return;
  }
  RestoreRegisters(r1, r14, r15, r16, r17, r18, r19, r20, r21, r22, r23,
                   r24, r25, r26, r27, r28, r29, r30, r31, f14, f15, f16,
                   f17, f18, f19, f20, f21, f22, f23, f24, f25, f26, f27,
                   f28, f29, f30, f31);
  RestoreVectors(v20, v21, v22, v23, v24, v25, v26, v27, v28, v29, v30, v31);
  cr2 = g_saved_switch_cr[0];
  cr3 = g_saved_switch_cr[1];
  cr4 = g_saved_switch_cr[2];
  g_saved_switch_active = false;
}
