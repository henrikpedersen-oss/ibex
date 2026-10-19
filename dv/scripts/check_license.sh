#!/usr/bin/env bash
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Licence seats for the EDA features this project's flows check out: issued, in use, and who holds
# them (user, host, since). Runs on nyx, where the Cadence tools and the licence server are reachable.
#
#   check_license.sh            every feature below
#   LICENSE_FEATURES="Genus_Synthesis jasper_papp" check_license.sh
#
# lmutil is Cadence's FlexLM client. On NixOS it cannot be exec'd directly (no /lib64 loader), and
# the copy under ddi/ is a ksh wrapper (no ksh on nyx), so Jasper's ELF lmutil is run through the
# glibc loader of nixpkgs. No Cadence FHS is needed for it.
set -euo pipefail

LICENSE_SERVER="${LICENSE_SERVER:-5280@cadence-license.services.lowrisc.dev}"
LMUTIL="${LMUTIL:-/nas/lowrisc/tools/cadence/jasper/2025.09/Linux64/bin/lmutil}"
# Feature -> what uses it here.
FEATURES_DEFAULT="
Xcelium_Single_Core:xrun/xmsim (UVM, TestRIG, compliance, RTOS SoC, block bench)
Affirma_sim_analysis_env:xrun/SimVision
Integrated_Metrics_Center:imc (coverage merge, reports)
jasper_papp:Jasper (formal-riscv, formal-cheriot, VeriCHERI)
jasper_pint:Jasper (proof engines)
jasper_pcov:Jasper (formal-cov UNR)
Genus_Synthesis:Genus (genus-synth)
Conformal_Asic:Conformal LEC (genus-lec)
Conformal_Ultra:Conformal LEC (genus-lec)
"

if [[ ! -x "${LMUTIL}" ]]; then
  echo "check_license: ${LMUTIL} not found: run this on nyx (make check-license does, over ssh)" >&2
  exit 2
fi
export PATH="${PATH}:/run/current-system/sw/bin"
glibc="$(nix build --no-link --print-out-paths 'nixpkgs#glibc.out' 2>/dev/null | head -1)"
loader="${glibc}/lib/ld-linux-x86-64.so.2"
[[ -x "${loader}" ]] || { echo "check_license: no glibc loader (nix build nixpkgs#glibc.out)" >&2; exit 2; }

status="$("${loader}" "${LMUTIL}" lmstat -c "${LICENSE_SERVER}" -a 2>&1)" || true
if ! grep -q "license server UP" <<< "${status}"; then
  echo "check_license: licence server ${LICENSE_SERVER} not UP:" >&2
  grep -iE "error|down|cannot" <<< "${status}" | head -5 >&2
  exit 1
fi

if [[ -n "${LICENSE_FEATURES:-}" ]]; then
  features=""
  for f in ${LICENSE_FEATURES}; do
    known="$(grep "^${f}:" <<< "${FEATURES_DEFAULT}" || true)"
    features+="${known:-${f}:}"$'\n'
  done
else
  features="${FEATURES_DEFAULT}"
fi

echo "Licence server ${LICENSE_SERVER}, $(date '+%Y-%m-%d %H:%M')"
printf '%-28s %6s %6s  %s\n' "Feature" "issued" "in use" "used by / holders"
printf '%-28s %6s %6s  %s\n' "-------" "------" "------" "-----------------"
while IFS=: read -r feat what; do
  [[ -z "${feat}" ]] && continue
  # "Users of F:  (Total of N licenses issued;  Total of M licenses in use)", then one line per
  # holder: "    user host display (vX) (server/port handle), start Day MM/DD HH:MM"
  block="$(awk -v f="${feat}" '
    $0 ~ "^Users of " f ":" { on = 1; print; next }
    on && /^Users of / { exit }
    on && /, start / { print }' <<< "${status}")"
  if [[ -z "${block}" ]]; then
    printf '%-28s %6s %6s  %s\n' "${feat}" "-" "-" "not on this server${what:+ (${what})}"
    continue
  fi
  issued="$(sed -n '1s/.*Total of \([0-9]*\) licen[sc]e[s]* issued.*/\1/p' <<< "${block}")"
  inuse="$(sed -n '1s/.*Total of \([0-9]*\) licen[sc]e[s]* in use.*/\1/p' <<< "${block}")"
  note="${what}"
  [[ "${inuse}" -ge "${issued}" && "${issued}" -gt 0 ]] && note="ALL IN USE${note:+ -- ${note}}"
  printf '%-28s %6s %6s  %s\n' "${feat}" "${issued}" "${inuse}" "${note}"
  # Holders: user@host, since.
  tail -n +2 <<< "${block}" | awk '{
    user = $1; host = $2; since = $0; sub(/.*, start /, "", since);
    printf "%-28s %6s %6s    %s@%s since %s\n", "", "", "", user, host, since }'
done <<< "${features}"
exit 0
