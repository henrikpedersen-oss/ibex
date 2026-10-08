// Copyright lowRISC Contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Directed test for the CHERIoT hardware load barrier (ibex_trvk).
//
// Why this exists, when cwe415/cwe416 already cover use-after-free:
//
// Those tests only check one direction — that a stale capability loses its tag.
// A load barrier that cleared *every* tag would pass them both, and so would a
// barrier wired to a constant "always revoked". Worse, the reverse stub is what
// we actually shipped for a while: sonata_system.sv fed trvk_revbm_rdata_i a
// constant 32'h0 ("nothing is ever revoked"), and the RTOS suite's own
// test_revoke still reported "Checked that all allocations have been
// deallocated (0..7 of 8)". A test that passes whether or not the hardware is
// connected tells us nothing.
//
// So this test drives the shadow bitmap *directly* over MMIO rather than going
// through heap_free, and asserts both directions on the same object:
//
//   Phase 1  bit clear  -> reloaded capability keeps its tag   (no false positive)
//   Phase 2  bit set    -> reloaded capability loses its tag   (barrier fires)
//   Phase 3  bit clear  -> reloaded capability keeps its tag   (recovers, not latched)
//
// Phase 1 is the one that makes the result meaningful: it fails if the barrier
// is stuck clearing everything, which is the failure mode the CWE tests cannot
// see. Phase 3 catches a barrier that latches on first fire.
//
// Bitmap geometry (sonata board.json and tl_main_pkg.sv agree):
//   shadow region        0x30000000, 0x800 bytes = 512 words = 16384 bits
//   revokable_memory     starts 0x00100000  (== ibex_top's trvk_heap_base_addr_i)
//   one bit per 8 bytes of revokable memory
// ibex_trvk computes its index the same way:
//   revbm_cap_addr = cap_base - heap_base_addr_i   (ibex_trvk.sv:328)
// so the bit is selected by the *base of the loaded capability*, not by the
// address the capability was loaded from.

#include <compartment.h>
#include <debug.hh>
#include "../common/sim_exit.hh"
#include <stdlib.h>
#include <thread.h>

using Debug = ConditionalDebug<true, "Revocation barrier">;

namespace
{
	/// Start of revokable memory; must match board.json revokable_memory_start
	/// and the trvk_heap_base_addr_i tie-off in sonata_system.sv.
	constexpr size_t RevokableMemoryStart = 0x0010'0000;

	/// One shadow bit per this many bytes of revokable memory.
	constexpr size_t BytesPerShadowBit = 8;

	/// Shadow bitmap as words. The device is named "shadow" in board.json.
	/// MMIO_CAPABILITY already yields a volatile pointer, so the type argument
	/// must not repeat it.
	volatile uint32_t *shadow_bitmap()
	{
		return MMIO_CAPABILITY(uint32_t, shadow);
	}

	/// Index of the shadow bit covering `addr`, as (word, bit-in-word).
	void shadow_index(size_t addr, size_t &word, size_t &bit)
	{
		size_t bitIndex = (addr - RevokableMemoryStart) / BytesPerShadowBit;
		word            = bitIndex / 32;
		bit             = bitIndex % 32;
	}

	void set_shadow_bit(size_t addr, bool value)
	{
		size_t word, bit;
		shadow_index(addr, word, bit);
		volatile uint32_t *bitmap = shadow_bitmap();
		uint32_t           v      = bitmap[word];
		bitmap[word] = value ? (v | (uint32_t(1) << bit)) : (v & ~(uint32_t(1) << bit));
	}

	/// The hardware revoker's registers (Sonata rev_ctl; same layout as
	/// platform-hardware_revoker.hh). With the CHERIoT memory subsystem these
	/// drive its revocation engine (TRBE) through cheriot_rev_ctl_trbe.sv.
	struct RevokerInterface
	{
		uint32_t base;
		uint32_t top;
		uint32_t control;
		uint32_t epoch; ///< low bit set while a sweep runs; +2 per sweep
		uint32_t interruptStatus;
		uint32_t interruptRequested;
	};

	volatile RevokerInterface *revoker()
	{
		return MMIO_CAPABILITY(RevokerInterface, revoker);
	}

	/// Capabilities stored in this compartment's globals, which lie inside the
	/// revoker's sweep range (compartment globals to end of heap, set by the
	/// allocator at boot). volatile so every access is a real load/store.
	void *volatile sweptSlot;
	void *volatile keptSlot;
	/// Untagged copies of the swept and the kept capability, also in the sweep
	/// range: a revocation engine that only invalidates leaves them untagged
	/// and unchanged (test_revocation_sweep).
	void *volatile sweptUntaggedSlot;
	void *volatile keptUntaggedSlot;

	/// The barrier test's object, stored once with its shadow bit clear. The
	/// barrier strips tags on the way into a register and never touches the
	/// copy in memory, so every phase reloads this same copy.
	///
	/// volatile so every read is a real load for the barrier to act on --
	/// without that every phase would trivially "pass".
	void *volatile barrierSlot;

	/// Reload the barrier test's object and report whether it kept its tag.
	bool tag_survives_reload()
	{
		void *reload = barrierSlot;
		return __builtin_cheri_tag_get(reload);
	}
} // namespace

/// Returns true if every phase behaved as expected.
bool test_revocation_barrier()
{
	Timeout t{5};
	void   *p = heap_allocate(&t, MALLOC_CAPABILITY, 64);
	if (!__builtin_cheri_tag_get(p))
	{
		Debug::log("FAIL: heap_allocate returned an untagged capability");
		return false;
	}

	size_t base = __builtin_cheri_base_get(p);
	size_t word, bit;
	shadow_index(base, word, bit);
	Debug::log("object {} base {} -> shadow word {} bit {}", p, base, word, bit);

	if (base < RevokableMemoryStart)
	{
		Debug::log("FAIL: allocation at {} is below revokable memory start {}",
		           base,
		           RevokableMemoryStart);
		heap_free(MALLOC_CAPABILITY, p);
		return false;
	}

	// While the bit is set, *any* load of a capability to this object loses its
	// tag -- including a callee restoring the saved register that holds `p`.
	// debug_log_message_write saves and restores cs1, which is where `p` lives,
	// so a Debug::log between setting and clearing the bit strips `p` itself:
	// that is what made phase 3 fail on 2026-09-29 with a correct barrier. So
	// the three phases run back to back with no calls but the leaf
	// set_shadow_bit, every phase reloads the copy stored here with the bit
	// clear, and the results are logged afterwards.
	set_shadow_bit(base, false);
	barrierSlot = p;

	// Phase 1: bit clear -> tag must survive. Guards against a barrier that
	// clears every tag, and against one wired to a constant "always revoked".
	bool phase1 = tag_survives_reload();

	// Phase 2: bit set -> tag must be cleared. The actual revocation check.
	// Fails if the barrier is stubbed to "nothing is ever revoked", which is
	// how sonata_system.sv used to wire it.
	set_shadow_bit(base, true);
	bool phase2 = !tag_survives_reload();

	// Phase 3: bit clear again -> tag must survive. Catches a barrier that
	// latches after its first fire.
	set_shadow_bit(base, false);
	bool phase3 = tag_survives_reload();

	if (phase1)
	{
		Debug::log("PASS phase 1: tag survived reload with shadow bit clear");
	}
	else
	{
		Debug::log("FAIL phase 1: tag cleared with shadow bit CLEAR "
		           "(barrier is revoking unconditionally)");
	}
	if (phase2)
	{
		Debug::log("PASS phase 2: tag cleared on reload with shadow bit set");
	}
	else
	{
		Debug::log("FAIL phase 2: tag survived with shadow bit SET "
		           "(barrier is not reading the bitmap)");
	}
	if (phase3)
	{
		Debug::log("PASS phase 3: tag survived again after clearing shadow bit");
	}
	else
	{
		Debug::log("FAIL phase 3: tag still cleared after shadow bit cleared "
		           "(barrier latched)");
	}

	// The bit is clear again, so this reload keeps its tag even if `p`'s
	// register copy was stripped.
	void *freeMe = barrierSlot;
	barrierSlot  = nullptr;
	heap_free(MALLOC_CAPABILITY, freeMe);
	return phase1 && phase2 && phase3;
}

/// Sweep check: the revocation engine clears the tag of a revoked capability
/// *in memory*, and of nothing else.
///
/// Phases 1-3 only exercise the load barrier, which strips the tag on the way
/// into a register. Here the barrier is taken out of the picture: the bitmap
/// bit is cleared again before the stored copies are read back, so only a
/// sweep can have removed a tag.
///
///   sweptSlot = p, keptSlot = q; set p's bit; run one sweep; clear p's bit
///   -> sweptSlot must have lost its tag (the sweep ran and revoked it)
///   -> keptSlot must still have its tag (the sweep did not clear everything)
///
/// Then the TRBE invalidate-only check (testplan bus_master_trbe_invalidate_only):
/// the TRBE writes memory without the core's capability checks, so it must
/// write nothing but tag clears. After the sweep, compared bit for bit with
/// CSEQX (__builtin_cheri_equal_exact, which includes the tag):
///   -> sweptSlot == p with its tag cleared (no other bit written)
///   -> keptSlot == q (not written at all)
///   -> untagged copies of p and of q, stored beside them, are unchanged (a
///      tag is never set, and data the sweep looks at is never written)
///
/// Without a sweep engine (Sonata's default build) the epoch never moves; that
/// is reported as SKIP, not failure. The CHERIoT memory subsystem build
/// (make sonata-revocation-cheriot-mem-xlm) requires "PASS sweep".
enum class SweepResult
{
	Pass,
	Fail,
	Skip
};

SweepResult test_revocation_sweep()
{
	Timeout t{5};
	void   *p = heap_allocate(&t, MALLOC_CAPABILITY, 64);
	void   *q = heap_allocate(&t, MALLOC_CAPABILITY, 64);
	if (!__builtin_cheri_tag_get(p) || !__builtin_cheri_tag_get(q))
	{
		Debug::log("FAIL sweep: heap_allocate returned an untagged capability");
		return SweepResult::Fail;
	}
	size_t pBase = __builtin_cheri_base_get(p);
	size_t qBase = __builtin_cheri_base_get(q);
	size_t pWord, pBit, qWord, qBit;
	shadow_index(pBase, pWord, pBit);
	shadow_index(qBase, qWord, qBit);
	if (pWord == qWord && pBit == qBit)
	{
		Debug::log("FAIL sweep: the two objects share a shadow bit");
		return SweepResult::Fail;
	}

	// Expected values, taken before p's shadow bit is set: while it is set a
	// callee restoring the register that holds p strips p's tag, and these
	// untagged values cannot be stripped.
	void *pUntagged   = __builtin_cheri_tag_clear(p);
	void *qUntagged   = __builtin_cheri_tag_clear(q);
	sweptSlot         = p;
	keptSlot          = q;
	sweptUntaggedSlot = pUntagged;
	keptUntaggedSlot  = qUntagged;
	set_shadow_bit(pBase, true);

	// Start one sweep, as the allocator's driver does (system_bg_revoker_kick):
	// only from an even epoch, by writing control 0 then 1.
	volatile RevokerInterface *dev = revoker();
	uint32_t                   start;
	int                        waited = 0;
	// ThreadSleepNoEarlyWake on every sleep here: without it a sleeping thread
	// is woken as soon as no other thread is runnable -- always, in this test --
	// so the 50 polls below took a few thousand cycles in all and gave up on
	// 2026-09-29 while a sweep that finished ~85k cycles after starting was
	// still running (trbe_monitor in sonata-xlm/top_sonata_xlm.sv).
	while (((start = dev->epoch) & 1) && waited++ < 50)
	{
		Timeout s{1};
		thread_sleep(&s, ThreadSleepNoEarlyWake);
	}
	dev->control = 0;
	dev->control = 1;

	// Wait for the epoch to advance by a full sweep (+2 from an even value).
	// One tick (400k cycles) is ample: a full sweep of the ~16k capabilities
	// takes ~85k cycles; 50 ticks is the hang bound.
	bool started = false;
	bool done    = false;
	for (int i = 0; i < 50 && !done; i++)
	{
		uint32_t now = dev->epoch;
		started |= (now != start);
		done = (now - start) >= 2 && !(now & 1);
		if (!done)
		{
			Timeout s{1};
			thread_sleep(&s, ThreadSleepNoEarlyWake);
		}
	}

	set_shadow_bit(pBase, false);
	void *swept    = sweptSlot;
	void *kept     = keptSlot;
	bool  sweptTag = __builtin_cheri_tag_get(swept);
	bool  keptTag  = __builtin_cheri_tag_get(kept);
	bool  sweptOnlyTag =
	  __builtin_cheri_equal_exact(swept, pUntagged);
	bool keptExact = __builtin_cheri_equal_exact(kept, q);
	bool untaggedKept =
	  __builtin_cheri_equal_exact(sweptUntaggedSlot, pUntagged) &&
	  __builtin_cheri_equal_exact(keptUntaggedSlot, qUntagged);
	sweptSlot         = nullptr;
	keptSlot          = nullptr;
	sweptUntaggedSlot = nullptr;
	keptUntaggedSlot  = nullptr;
	heap_free(MALLOC_CAPABILITY, p);
	heap_free(MALLOC_CAPABILITY, q);

	if (!started)
	{
		Debug::log("SKIP sweep: the revoker's epoch never moved "
		           "(no revocation engine in this build)");
		return SweepResult::Skip;
	}
	if (!done)
	{
		Debug::log("FAIL sweep: a sweep started but did not finish (epoch {} -> {})",
		           start,
		           dev->epoch);
		return SweepResult::Fail;
	}
	bool passed = true;
	if (sweptTag)
	{
		Debug::log("FAIL sweep: revoked capability kept its tag in memory "
		           "(the sweep did not clear it)");
		passed = false;
	}
	if (!keptTag)
	{
		Debug::log("FAIL sweep: unrevoked capability lost its tag in memory "
		           "(the sweep cleared too much)");
		passed = false;
	}
	if (passed)
	{
		Debug::log("PASS sweep: revoked capability cleared in memory, "
		           "unrevoked one kept (epoch {} -> {})",
		           start,
		           dev->epoch);
	}
	if (sweptOnlyTag && keptExact && untaggedKept)
	{
		Debug::log("PASS TRBE invalidate-only: the sweep changed only the "
		           "revoked capability's tag");
	}
	else
	{
		Debug::log("FAIL TRBE invalidate-only: revoked word {} (expected {}), "
		           "kept word {}, untagged copies {}",
		           sweptOnlyTag ? "tag cleared only" : "changed otherwise",
		           pUntagged,
		           keptExact ? "unchanged" : "CHANGED",
		           untaggedKept ? "unchanged" : "CHANGED");
		passed = false;
	}
	return passed ? SweepResult::Pass : SweepResult::Fail;
}

/// Thread entry point. Prints the strings test_runner.py greps for.
///
/// CHERIoT RTOS threads must not return, so this loops forever after printing
/// the result -- same shape as juliet_orchestrator's run_juliet_tests. The
/// __cheri_compartment attribute (not extern "C") is what makes the exported
/// symbol name match what the firmware linker script expects.
[[noreturn]] void __cheri_compartment("revocation_test") run_revocation_tests()
{
	Debug::log("Starting hardware load-barrier test");

	bool barrierOk = test_revocation_barrier();
	bool sweepOk   = test_revocation_sweep() != SweepResult::Fail;
	if (barrierOk && sweepOk)
	{
		Debug::log("All tests finished");
	}
	else
	{
		Debug::log("Test(s) Failed");
	}
	sim_exit();

	while (true)
	{
		Timeout t{1000};
		thread_sleep(&t);
	}
}
