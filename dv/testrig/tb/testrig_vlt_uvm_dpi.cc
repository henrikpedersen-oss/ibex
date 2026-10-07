// UVM DPI for the TestRIG build in testrig_vlt_build.sh: $UVM_HOME/dpi/uvm_dpi.cc without
// uvm_hdl.c. uvm_hdl.c only has VCS/Questa/Xcelium back ends (#error otherwise); the TestRIG
// bench makes no uvm_hdl_* calls, so the SV side is built with UVM_HDL_NO_DPI. What is kept is
// what the bench needs: the command-line processor (+uvm_set_type_override, +UVM_TESTNAME, ...),
// which reads the simulator's arguments through vpi_get_vlog_info, plus the regex helpers.

#ifdef __cplusplus
extern "C" {
#endif

#include <stdlib.h>
#include "uvm_dpi.h"

int uvm_re_match(const char *re, const char *str);
const char *uvm_glob_to_re(const char *glob);
void push_data(int lvl, char *entry, int cmd);
void walk_level(int lvl, int argc, char **argv, int cmd);
const char *uvm_dpi_get_next_arg_c(int init);
extern char *uvm_dpi_get_tool_name_c();
extern char *uvm_dpi_get_tool_version_c();
extern regex_t *uvm_dpi_regcomp(char *pattern);
extern int uvm_dpi_regexec(regex_t *re, char *str);
extern void uvm_dpi_regfree(regex_t *re);

#include "uvm_common.c"
#include "uvm_regex.cc"
#include "uvm_svcmd_dpi.c"

#ifdef __cplusplus
}
#endif
