/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

function clause ext_is_CSR_defined (0x008, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */
function clause ext_is_CSR_defined (0xC20, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */
function clause ext_is_CSR_defined (0xC21, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */
function clause ext_is_CSR_defined (0xC22, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */

function clause ext_is_CSR_defined (0x009, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */
function clause ext_is_CSR_defined (0x00A, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */
function clause ext_is_CSR_defined (0x00F, _) = haveVExt() /* local: ibex has no V (VENDORED_FROM) */

function clause ext_read_CSR (0x009) = Some (zero_extend(vcsr[vxsat]))
function clause ext_read_CSR (0x00A) = Some (zero_extend(vcsr[vxrm]))
function clause ext_read_CSR (0x00F) = Some (zero_extend(vcsr.bits))

function clause ext_read_CSR (0x009) = Some (zero_extend(vcsr[vxsat]))
function clause ext_read_CSR (0x00A) = Some (zero_extend(vcsr[vxrm]))
function clause ext_read_CSR (0x00F) = Some (zero_extend(vcsr.bits))

function clause ext_write_CSR (0x009, value) = { ext_write_vcsr (vcsr[vxrm], value[0 .. 0]); Some(zero_extend(vcsr[vxsat])) }
function clause ext_write_CSR (0x00A, value) = { ext_write_vcsr (value[1 .. 0], vcsr[vxsat]); Some(zero_extend(vcsr[vxrm])) }
function clause ext_write_CSR (0x00F, value) = { ext_write_vcsr (value [2 .. 1], value [0 .. 0]); Some(zero_extend(vcsr.bits)) }
