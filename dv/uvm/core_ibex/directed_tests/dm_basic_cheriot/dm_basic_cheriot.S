# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# dm_basic in CHERIoT mode (+enable_cheriot_seq=1): see dm_basic/dm_basic.S for the test, its
# registers and exit codes.

#define DM_CHERIOT 1
#include "dm_basic/dm_basic.S"
