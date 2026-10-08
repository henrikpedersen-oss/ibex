// Copyright lowRISC Contributors.
// SPDX-License-Identifier: Apache-2.0
//
// CHERIoT compartment implementing clang_purecap_input (FAULT test):
//   "write through a capability whose STORE permission has been removed"
//
// DECLARE_TEST_FAULT.  The original test uses the FreeBSD __cheri_input
// qualifier to strip STORE/STORE_CAPABILITY from a pointer and then verifies
// that a store traps.  We replicate the semantic using
// __builtin_cheri_perms_and() to narrow the permissions explicitly, which
// is the canonical CHERIoT way to produce a read-only capability at runtime.
//
// The attempted store triggers a CHERI store-permission fault; the
// compartment_error_handler returns ForceUnwind.  The orchestrator verifies
// the returned capability is invalid (address == -1).

// This wrapper defines its own compartment_error_handler (cheri_c_test_framework.h).
#define CHERI_C_OWN_ERROR_HANDLER
#include <compartment.h>
#include <debug.hh>
#include <stdint.h>
#include "cheriot_perms.h"

using Debug = ConditionalDebug<true, "cc-input">;

extern "C" ErrorRecoveryBehaviour
compartment_error_handler(ErrorState *frame, size_t mcause, size_t mtval)
{
	Debug::log("CHERI fault caught: mcause={} mtval={} pcc={}: ForceUnwind", mcause, mtval, frame->pcc);
	return ErrorRecoveryBehaviour::ForceUnwind;
}

// Strip STORE and STORE_CAPABILITY from *p, then attempt a store through the
// narrowed capability — this must fault with a CHERI store-permission trap.
__attribute__((noinline)) static void attempt_store_through_readonly(int *p)
{
	// Build a read-only (LOAD-only) capability from p.
	void *ro = __builtin_cheri_perms_and(
	    (void *)p,
	    __CHERI_CAP_PERMISSION_PERMIT_LOAD__ |
	    __CHERI_CAP_PERMISSION_PERMIT_LOAD_CAPABILITY__);

	// Check the permission really was removed. This used to be a __builtin_expect, which is a
	// compiler hint and checks nothing. If CAndPerm left Store in place, the store below would
	// succeed and the test would report "no fault" -- a CAndPerm bug reported as a missing
	// store-permission check. Report it as what it is and skip the store.
	if ((__builtin_cheri_perms_get(ro) & __CHERI_CAP_PERMISSION_PERMIT_STORE__) != 0)
	{
		Debug::log("FAIL: cc_input: CAndPerm left Store in place: perms {}", __builtin_cheri_perms_get(ro));
		return;
	}

	// This store must trigger a CHERI store-permission fault.
	*(volatile int *)ro = 42;
}

void *__cheri_compartment("cc_input") run_fault_input(void)
{
	int x = 47;
	attempt_store_through_readonly(&x);
	Debug::log("WARNING: no CHERI fault triggered in cc_input test");
	return nullptr;
}
