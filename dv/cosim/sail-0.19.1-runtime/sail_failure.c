/****************************************************************************/
/*     Sail                                                                 */
/*                                                                          */
/*  Sail and the Sail architecture models here, comprising all files and    */
/*  directories except the ASL-derived Sail code in the aarch64 directory,  */
/*  are subject to the BSD two-clause licence below.                        */
/*                                                                          */
/*  The ASL derived parts of the ARMv8.3 specification in                   */
/*  aarch64/no_vector and aarch64/full are copyright ARM Ltd.               */
/*                                                                          */
/*  Copyright (c) 2013-2021                                                 */
/*    Kathyrn Gray                                                          */
/*    Shaked Flur                                                           */
/*    Stephen Kell                                                          */
/*    Gabriel Kerneis                                                       */
/*    Robert Norton-Wright                                                  */
/*    Christopher Pulte                                                     */
/*    Peter Sewell                                                          */
/*    Alasdair Armstrong                                                    */
/*    Brian Campbell                                                        */
/*    Thomas Bauereiss                                                      */
/*    Anthony Fox                                                           */
/*    Jon French                                                            */
/*    Dominic Mulligan                                                      */
/*    Stephen Kell                                                          */
/*    Mark Wassell                                                          */
/*    Alastair Reid (Arm Ltd)                                               */
/*                                                                          */
/*  All rights reserved.                                                    */
/*                                                                          */
/*  This work was partially supported by EPSRC grant EP/K008528/1 <a        */
/*  href="http://www.cl.cam.ac.uk/users/pes20/rems">REMS: Rigorous          */
/*  Engineering for Mainstream Systems</a>, an ARM iCASE award, EPSRC IAA   */
/*  KTF funding, and donations from Arm.  This project has received         */
/*  funding from the European Research Council (ERC) under the European     */
/*  Union’s Horizon 2020 research and innovation programme (grant           */
/*  agreement No 789108, ELVER).                                            */
/*                                                                          */
/*  This software was developed by SRI International and the University of  */
/*  Cambridge Computer Laboratory (Department of Computer Science and       */
/*  Technology) under DARPA/AFRL contracts FA8650-18-C-7809 ("CIFV")        */
/*  and FA8750-10-C-0237 ("CTSRD").                                         */
/*                                                                          */
/*  SPDX-License-Identifier: BSD-2-Clause                                   */
/****************************************************************************/

#include "sail_failure.h"
#include <setjmp.h>

/* When sail_recovery_buf_active is non-zero, sail_match_failure and
 * sail_assert longjmp to sail_recovery_buf instead of calling exit().
 * The longjmp value encodes the failure type (1 = match failure, 2 = assert).
 * Set by cheriot_sail_cosim_step() around each zstep() call so that
 * unrecognized instruction encodings (which trigger sail_match_failure) are
 * handled gracefully rather than crashing the simulation. */
jmp_buf sail_recovery_buf;
int     sail_recovery_buf_active = 0;

#ifdef __cplusplus
extern "C" {
#endif

void sail_match_failure(const_sail_string msg)
{
  fprintf(stderr, "Pattern match failure in %s\n", msg);
  if (sail_recovery_buf_active) {
    longjmp(sail_recovery_buf, 1);
  }
  exit(EXIT_FAILURE);
}

unit sail_assert(bool b, const_sail_string msg)
{
  if (b) return UNIT;
  fprintf(stderr, "Assertion failed: %s\n", msg);
  if (sail_recovery_buf_active) {
    longjmp(sail_recovery_buf, 2);
  }
  exit(EXIT_FAILURE);
}

#ifdef __cplusplus
}
#endif
