// Copyright lowRISC Contributors.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT compartment wrapping clang_purecap_array (FAULT test):
//   "on-stack array accessed out-of-bounds → CHERI length fault"
//
// DECLARE_TEST_FAULT.  The original test accesses an int* derived from an
// 8-byte char buffer beyond its bounds; the first out-of-bounds int access
// triggers a CHERI length fault.  In CHERIoT the compartment_error_handler
// returns ForceUnwind, terminating the compartment call.  The orchestrator
// verifies the returned capability is invalid (address == -1).
//
// The original test counts multiple faults (FreeBSD resumable-exception
// model); we only verify that at least one fault fires.

#define TEST_CUSTOM_FRAMEWORK
// This wrapper defines its own compartment_error_handler (cheri_c_test_framework.h).
#define CHERI_C_OWN_ERROR_HANDLER
#include <compartment.h>
#include <debug.hh>

using Debug = ConditionalDebug<true, "cc-array">;

// compartment_error_handler: called by the CHERIoT switcher on any CHERI
// hardware exception inside this compartment.  ForceUnwind terminates the
// compartment call and lets the orchestrator observe the invalid return cap.
extern "C" ErrorRecoveryBehaviour
compartment_error_handler(ErrorState *frame, size_t mcause, size_t mtval)
{
	Debug::log("CHERI fault caught: mcause={} mtval={} pcc={}: ForceUnwind", mcause, mtval, frame->pcc);
	return ErrorRecoveryBehaviour::ForceUnwind;
}

// _Alignas is a C11 keyword with no C++ spelling; this wrapper compiles the upstream
// C file as C++, where it parses as a call and yields "error: expected expression"
// plus cascading "undeclared identifier" errors for the variable it qualifies.
// alignas is the C++ equivalent and accepts the same integral argument.
#ifndef _Alignas
#define _Alignas(x) alignas(x)
#endif

#include "clang-purecap/clang_purecap_array.c"

void *__cheri_compartment("cc_array") run_fault_array(void)
{
	run_test_clang_purecap_array();
	// Reached only if no fault fires — unexpected for this test.
	Debug::log("WARNING: no CHERI fault triggered in clang_purecap_array");
	return nullptr;
}
