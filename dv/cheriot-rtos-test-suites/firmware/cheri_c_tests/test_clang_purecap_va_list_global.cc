// Copyright lowRISC Contributors.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT compartment wrapping clang_purecap_va_list_global (FAULT test):
//   "a va_list stored in a global loses its tag; using it faults"
//
// DECLARE_TEST_FAULT. On CHERIoT the va_list is a stack-derived, local capability, so storing it
// in a global clears its tag, and the first va_arg through it must raise a CHERI tag violation
// (see cheriot_clang_purecap_va_list_global.c). compartment_error_handler returns ForceUnwind;
// the orchestrator verifies the returned capability is invalid (address == -1).
//
// Unlike the older fault wrappers, a pass also needs the checks this compartment makes before
// and in the fault: the assertions that run before the fault (among them that the reloaded
// va_list is untagged), and the handler's check that the fault is a tag violation, not some other
// fault earlier or later. Both count into test_failures, which the orchestrator reads with
// run_fault_va_list_global_failures() after the unwind.

#define TEST_CUSTOM_FRAMEWORK
// This wrapper defines its own compartment_error_handler (cheri_c_test_framework.h).
#define CHERI_C_OWN_ERROR_HANDLER
#include <cheri.hh>
#include <compartment.h>
#include <debug.hh>
#include <priv/riscv.h>

using Debug = ConditionalDebug<true, "cc-va-list-global">;

// CHERIoT port of the upstream test: expects a tag violation on the first va_arg (see its
// header).
#include "cheriot_clang_purecap_va_list_global.c"

extern "C" ErrorRecoveryBehaviour
compartment_error_handler(ErrorState *frame, size_t mcause, size_t mtval)
{
	Debug::log("CHERI fault caught: mcause={} mtval={} pcc={}: ForceUnwind",
	           mcause, mtval, frame->pcc);
	auto [cause, reg] = CHERI::extract_cheri_mtval(mtval);
	if (mcause != priv::MCAUSE_CHERI || cause != CHERI::CauseCode::TagViolation)
	{
		Debug::log("FAIL: expected a CHERI tag violation, got mcause={} cause={} register={}",
		           mcause, cause, reg);
		test_failures++;
	}
	return ErrorRecoveryBehaviour::ForceUnwind;
}

void *__cheri_compartment("cc_va_list_global") run_fault_va_list_global(void)
{
	run_test_clang_purecap_va_list_global();
	// Reached only if no fault fires — unexpected for this test.
	Debug::log("WARNING: no CHERI fault triggered in clang_purecap_va_list_global");
	return nullptr;
}

// Assertion failures before the fault, plus a fault of the wrong kind. test_failures is reset by
// the test body and survives the unwind, as compartment globals do.
int __cheri_compartment("cc_va_list_global") run_fault_va_list_global_failures(void)
{
	return test_failures;
}
