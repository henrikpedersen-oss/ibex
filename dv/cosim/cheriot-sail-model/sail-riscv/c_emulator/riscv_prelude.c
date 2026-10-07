#include "riscv_prelude.h"
#include "riscv_config.h"
#include "riscv_platform_impl.h"

/* Attempt to keep track of whether output is at the start of a line so that we
 * can produce nicer output if trace output interrupts terminal output. */
bool have_newline = true;

void ensure_newline()
{
  if (!have_newline)
    fputc('\n', trace_log);
}

unit print_string(sail_string prefix, sail_string msg)
{
  ensure_newline();
  fprintf(trace_log, "%s%s\n", prefix, msg);
  have_newline = true;
  return UNIT;
}

unit print_instr(sail_string s)
{
  ensure_newline();
  if (config_print_instr)
    fprintf(trace_log, "%s\n", s);
  have_newline = true;
  return UNIT;
}

unit print_reg(sail_string s)
{
  ensure_newline();
  if (config_print_reg)
    fprintf(trace_log, "%s\n", s);
  have_newline = true;
  return UNIT;
}

unit print_mem_access(sail_string s)
{
  ensure_newline();
  if (config_print_mem_access)
    fprintf(trace_log, "%s\n", s);
  have_newline = true;
  return UNIT;
}

unit print_platform(sail_string s)
{
  ensure_newline();
  if (config_print_platform)
    fprintf(trace_log, "%s\n", s);
  have_newline = true;
  return UNIT;
}

bool get_config_print_instr(unit u)
{
  return (config_print_instr) ? true : false;
}

bool get_config_print_reg(unit u)
{
  return (config_print_reg) ? true : false;
}

bool get_config_print_mem(unit u)
{
  return (config_print_mem_access) ? true : false;
}

bool get_config_print_platform(unit u)
{
  return (config_print_platform) ? true : false;
}

bool get_config_print_exception(unit u)
{
  return (config_print_exception) ? true : false;
}
