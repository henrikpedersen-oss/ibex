#pragma once

#include "sail.h"
#include "sail_config.h"
#include "rts.h"
#include "elf.h"
#ifdef __cplusplus
extern "C" {
#endif
extern void (*sail_rts_set_coverage_file)(const char *);

// enum zicondop
enum zzzicondop { zRISCV_CZERO_EQZ, zRISCV_CZERO_NEZ };

// type abbreviation xlenbits
typedef uint64_t zxlenbits;

// enum wxfunct6
enum zwxfunct6 { zWX_VADD, zWX_VSUB, zWX_VADDU, zWX_VSUBU };

// enum wvxfunct6
enum zwvxfunct6 { zWVX_VADD, zWVX_VSUB, zWVX_VADDU, zWVX_VSUBU, zWVX_VWMUL, zWVX_VWMULU, zWVX_VWMULSU };

// enum wvvfunct6
enum zwvvfunct6 { zWVV_VADD, zWVV_VSUB, zWVV_VADDU, zWVV_VSUBU, zWVV_VWMUL, zWVV_VWMULU, zWVV_VWMULSU };

// enum wvfunct6
enum zwvfunct6 { zWV_VADD, zWV_VSUB, zWV_VADDU, zWV_VSUBU };

// enum write_kind
enum zwrite_kind { zWrite_plain, zWrite_conditional, zWrite_release, zWrite_exclusive, zWrite_exclusive_release, zWrite_RISCV_release, zWrite_RISCV_strong_release, zWrite_RISCV_conditional, zWrite_RISCV_conditional_release, zWrite_RISCV_conditional_strong_release, zWrite_X86_locked };

// enum word_width
enum zword_width { zBYTE, zHALF, zWORD, zDOUBLE };

// type abbreviation word
typedef uint64_t zword;

// enum wmvxfunct6
enum zwmvxfunct6 { zWMVX_VWMACCU, zWMVX_VWMACC, zWMVX_VWMACCUS, zWMVX_VWMACCSU };

// enum wmvvfunct6
enum zwmvvfunct6 { zWMVV_VWMACCU, zWMVV_VWMACC, zWMVV_VWMACCSU };

// enum vxsgfunct6
enum zvxsgfunct6 { zVX_VSLIDEUP, zVX_VSLIDEDOWN, zVX_VRGATHER };

// enum vxmsfunct6
enum zvxmsfunct6 { zVXMS_VADC, zVXMS_VSBC };

// enum vxmfunct6
enum zvxmfunct6 { zVXM_VMADC, zVXM_VMSBC };

// enum vxmcfunct6
enum zvxmcfunct6 { zVXMC_VMADC, zVXMC_VMSBC };

// enum vxfunct6
enum zvxfunct6 { zVX_VADD, zVX_VSUB, zVX_VRSUB, zVX_VMINU, zVX_VMIN, zVX_VMAXU, zVX_VMAX, zVX_VAND, zVX_VOR, zVX_VXOR, zVX_VSADDU, zVX_VSADD, zVX_VSSUBU, zVX_VSSUB, zVX_VSLL, zVX_VSMUL, zVX_VSRL, zVX_VSRA, zVX_VSSRL, zVX_VSSRA };

// enum vxcmpfunct6
enum zvxcmpfunct6 { zVXCMP_VMSEQ, zVXCMP_VMSNE, zVXCMP_VMSLTU, zVXCMP_VMSLT, zVXCMP_VMSLEU, zVXCMP_VMSLE, zVXCMP_VMSGTU, zVXCMP_VMSGT };

// enum vvmsfunct6
enum zvvmsfunct6 { zVVMS_VADC, zVVMS_VSBC };

// enum vvmfunct6
enum zvvmfunct6 { zVVM_VMADC, zVVM_VMSBC };

// enum vvmcfunct6
enum zvvmcfunct6 { zVVMC_VMADC, zVVMC_VMSBC };

// enum vvfunct6
enum zvvfunct6 { zVV_VADD, zVV_VSUB, zVV_VMINU, zVV_VMIN, zVV_VMAXU, zVV_VMAX, zVV_VAND, zVV_VOR, zVV_VXOR, zVV_VRGATHER, zVV_VRGATHEREI16, zVV_VSADDU, zVV_VSADD, zVV_VSSUBU, zVV_VSSUB, zVV_VSLL, zVV_VSMUL, zVV_VSRL, zVV_VSRA, zVV_VSSRL, zVV_VSSRA };

// enum vvcmpfunct6
enum zvvcmpfunct6 { zVVCMP_VMSEQ, zVVCMP_VMSNE, zVVCMP_VMSLTU, zVVCMP_VMSLT, zVVCMP_VMSLEU, zVVCMP_VMSLE };

// enum vsetop
enum zvsetop { zVSETVLI, zVSETVL };

// type abbreviation vregtype
typedef lbits zvregtype;

// type abbreviation vreglenbits
typedef lbits zvreglenbits;

// enum vmlsop
enum zvmlsop { zVLM, zVSM };

// enum vlewidth
enum zvlewidth { zVLE8, zVLE16, zVLE32, zVLE64 };

// enum visgfunct6
enum zvisgfunct6 { zVI_VSLIDEUP, zVI_VSLIDEDOWN, zVI_VRGATHER };

// enum vimsfunct6
enum zvimsfunct6 { zVIMS_VADC };

// enum vimfunct6
enum zvimfunct6 { zVIM_VMADC };

// enum vimcfunct6
enum zvimcfunct6 { zVIMC_VMADC };

// enum vifunct6
enum zvifunct6 { zVI_VADD, zVI_VRSUB, zVI_VAND, zVI_VOR, zVI_VXOR, zVI_VSADDU, zVI_VSADD, zVI_VSLL, zVI_VSRL, zVI_VSRA, zVI_VSSRL, zVI_VSSRA };

// enum vicmpfunct6
enum zvicmpfunct6 { zVICMP_VMSEQ, zVICMP_VMSNE, zVICMP_VMSLEU, zVICMP_VMSLE, zVICMP_VMSGTU, zVICMP_VMSGT };

// enum vfwunary0
enum zvfwunary0 { zFWV_CVT_XU_F, zFWV_CVT_X_F, zFWV_CVT_F_XU, zFWV_CVT_F_X, zFWV_CVT_F_F, zFWV_CVT_RTZ_XU_F, zFWV_CVT_RTZ_X_F };

// enum vfunary1
enum zvfunary1 { zFVV_VSQRT, zFVV_VRSQRT7, zFVV_VREC7, zFVV_VCLASS };

// enum vfunary0
enum zvfunary0 { zFV_CVT_XU_F, zFV_CVT_X_F, zFV_CVT_F_XU, zFV_CVT_F_X, zFV_CVT_RTZ_XU_F, zFV_CVT_RTZ_X_F };

// enum vfnunary0
enum zvfnunary0 { zFNV_CVT_XU_F, zFNV_CVT_X_F, zFNV_CVT_F_XU, zFNV_CVT_F_X, zFNV_CVT_F_F, zFNV_CVT_ROD_F_F, zFNV_CVT_RTZ_XU_F, zFNV_CVT_RTZ_X_F };

// enum vext8funct6
enum zvext8funct6 { zVEXT8_ZVF8, zVEXT8_SVF8 };

// enum vext4funct6
enum zvext4funct6 { zVEXT4_ZVF4, zVEXT4_SVF4 };

// enum vext2funct6
enum zvext2funct6 { zVEXT2_ZVF2, zVEXT2_SVF2 };

// enum uop
enum zuop { zRISCV_LUI, zRISCV_AUIPC };

// enum trans_kind
enum ztrans_kind { zTransaction_start, zTransaction_commit, zTransaction_abort };

// type abbreviation tagaddrbits
typedef uint64_t ztagaddrbits;

// enum sopw
enum zsopw { zRISCV_SLLIW, zRISCV_SRLIW, zRISCV_SRAIW };

// enum sop
enum zsop { zRISCV_SLLI, zRISCV_SRLI, zRISCV_SRAI };

// enum seed_opst
enum zseed_opst { zBIST, zES16, zWAIT, zDEAD };

// type abbreviation screg
typedef uint64_t zscreg;

// enum ropw
enum zropw { zRISCV_ADDW, zRISCV_SUBW, zRISCV_SLLW, zRISCV_SRLW, zRISCV_SRAW };

// enum rop
enum zrop { zRISCV_ADD, zRISCV_SUB, zRISCV_SLL, zRISCV_SLT, zRISCV_SLTU, zRISCV_XOR, zRISCV_SRL, zRISCV_SRA, zRISCV_OR, zRISCV_AND };

// enum rmvvfunct6
enum zrmvvfunct6 { zMVV_VREDSUM, zMVV_VREDAND, zMVV_VREDOR, zMVV_VREDXOR, zMVV_VREDMINU, zMVV_VREDMIN, zMVV_VREDMAXU, zMVV_VREDMAX };

// enum rivvfunct6
enum zrivvfunct6 { zIVV_VWREDSUMU, zIVV_VWREDSUM };

// enum rfvvfunct6
enum zrfvvfunct6 { zFVV_VFREDOSUM, zFVV_VFREDUSUM, zFVV_VFREDMAX, zFVV_VFREDMIN, zFVV_VFWREDOSUM, zFVV_VFWREDUSUM };

// enum regor
enum zregor { zrs_1, zrs_2, zrs_na };

// type abbreviation regidx
typedef uint64_t zregidx;

// enum read_kind
enum zread_kind { zRead_plain, zRead_reserve, zRead_acquire, zRead_exclusive, zRead_exclusive_acquire, zRead_stream, zRead_ifetch, zRead_RISCV_acquire, zRead_RISCV_strong_acquire, zRead_RISCV_reserved, zRead_RISCV_reserved_acquire, zRead_RISCV_reserved_strong_acquire, zRead_X86_locked };

// type abbreviation pteAttribs
typedef uint64_t zpteAttribs;

// enum pmpMatch
enum zpmpMatch { zPMP_Success, zPMP_Continue, zPMP_Fail };

// enum pmpAddrMatch
enum zpmpAddrMatch { zPMP_NoMatch, zPMP_PartialMatch, zPMP_Match };

// type abbreviation paddr32
typedef uint64_t zpaddr32;

// union option<u>
enum kind_zoptionzIuzK { Kind_zNonezIuzK, Kind_zSomezIuzK };

struct zoptionzIuzK {
  enum kind_zoptionzIuzK kind;
  union {
    struct { unit zNonezIuzK; };
    struct { unit zSomezIuzK; };
  } variants;
};

// union option<s>
enum kind_zoptionzIszK { Kind_zNonezIszK, Kind_zSomezIszK };

struct zoptionzIszK {
  enum kind_zoptionzIszK kind;
  union {
    struct { unit zNonezIszK; };
    struct { sail_string zSomezIszK; };
  } variants;
};

// union option<b>
enum kind_zoptionzIbzK { Kind_zNonezIbzK, Kind_zSomezIbzK };

struct zoptionzIbzK {
  enum kind_zoptionzIbzK kind;
  union {
    struct { unit zNonezIbzK; };
    struct { lbits zSomezIbzK; };
  } variants;
};

// union option<Eread_kind%>
enum kind_zoptionzIEread_kindz5zK { Kind_zNonezIEread_kindz5zK, Kind_zSomezIEread_kindz5zK };

struct zoptionzIEread_kindz5zK {
  enum kind_zoptionzIEread_kindz5zK kind;
  union {
    struct { unit zNonezIEread_kindz5zK; };
    struct { enum zread_kind zSomezIEread_kindz5zK; };
  } variants;
};

// struct tuple_(%bv, %bool)
struct ztuple_z8z5bvzCz0z5boolz9 {
  lbits ztup0;
  bool ztup1;
};

// union option<(b,o)>
enum kind_zoptionzIz8bzCoz9zK { Kind_zNonezIz8bzCoz9zK, Kind_zSomezIz8bzCoz9zK };

struct zoptionzIz8bzCoz9zK {
  enum kind_zoptionzIz8bzCoz9zK kind;
  union {
    struct { unit zNonezIz8bzCoz9zK; };
    struct { struct ztuple_z8z5bvzCz0z5boolz9 zSomezIz8bzCoz9zK; };
  } variants;
};

// struct tuple_(%bv, %bv)
struct ztuple_z8z5bvzCz0z5bvz9 {
  lbits ztup0;
  lbits ztup1;
};

// union option<(b,b)>
enum kind_zoptionzIz8bzCbz9zK { Kind_zNonezIz8bzCbz9zK, Kind_zSomezIz8bzCbz9zK };

struct zoptionzIz8bzCbz9zK {
  enum kind_zoptionzIz8bzCbz9zK kind;
  union {
    struct { unit zNonezIz8bzCbz9zK; };
    struct { struct ztuple_z8z5bvzCz0z5bvz9 zSomezIz8bzCbz9zK; };
  } variants;
};

// type abbreviation pmp_addr_range
typedef struct zoptionzIz8bzCbz9zK zpmp_addr_range;

// enum nxsfunct6
enum znxsfunct6 { zNXS_VNSRL, zNXS_VNSRA };

// enum nxfunct6
enum znxfunct6 { zNX_VNCLIPU, zNX_VNCLIP };

// enum nvsfunct6
enum znvsfunct6 { zNVS_VNSRL, zNVS_VNSRA };

// enum nvfunct6
enum znvfunct6 { zNV_VNCLIPU, zNV_VNCLIP };

// enum nisfunct6
enum znisfunct6 { zNIS_VNSRL, zNIS_VNSRA };

// enum nifunct6
enum znifunct6 { zNI_VNCLIPU, zNI_VNCLIP };

// enum mvxmafunct6
enum zmvxmafunct6 { zMVX_VMACC, zMVX_VNMSAC, zMVX_VMADD, zMVX_VNMSUB };

// enum mvxfunct6
enum zmvxfunct6 { zMVX_VAADDU, zMVX_VAADD, zMVX_VASUBU, zMVX_VASUB, zMVX_VSLIDE1UP, zMVX_VSLIDE1DOWN, zMVX_VMUL, zMVX_VMULH, zMVX_VMULHU, zMVX_VMULHSU, zMVX_VDIVU, zMVX_VDIV, zMVX_VREMU, zMVX_VREM };

// enum mvvmafunct6
enum zmvvmafunct6 { zMVV_VMACC, zMVV_VNMSAC, zMVV_VMADD, zMVV_VNMSUB };

// enum mvvfunct6
enum zmvvfunct6 { zMVV_VAADDU, zMVV_VAADD, zMVV_VASUBU, zMVV_VASUB, zMVV_VMUL, zMVV_VMULH, zMVV_VMULHU, zMVV_VMULHSU, zMVV_VDIVU, zMVV_VDIV, zMVV_VREMU, zMVV_VREM };

// enum mmfunct6
enum zmmfunct6 { zMM_VMAND, zMM_VMNAND, zMM_VMANDNOT, zMM_VMXOR, zMM_VMOR, zMM_VMNOR, zMM_VMORNOT, zMM_VMXNOR };

// type abbreviation mem_meta
typedef bool zmem_meta;

// enum maskfunct3
enum zmaskfunct3 { zVV_VMERGE, zVI_VMERGE, zVX_VMERGE };

// enum iop
enum ziop { zRISCV_ADDI, zRISCV_SLTI, zRISCV_SLTIU, zRISCV_XORI, zRISCV_ORI, zRISCV_ANDI };

// union interrupt_set
enum kind_zinterrupt_set { Kind_zInts_Delegated, Kind_zInts_Empty, Kind_zInts_Pending };

struct zinterrupt_set {
  enum kind_zinterrupt_set kind;
  union {
    struct { uint64_t zInts_Delegated; };
    struct { unit zInts_Empty; };
    struct { uint64_t zInts_Pending; };
  } variants;
};

// struct htif_cmd
struct zhtif_cmd {uint64_t zbits;};

// type abbreviation half
typedef uint64_t zhalf;

// enum fwvvmafunct6
enum zfwvvmafunct6 { zFWVV_VMACC, zFWVV_VNMACC, zFWVV_VMSAC, zFWVV_VNMSAC };

// enum fwvvfunct6
enum zfwvvfunct6 { zFWVV_VADD, zFWVV_VSUB, zFWVV_VMUL };

// enum fwvfunct6
enum zfwvfunct6 { zFWV_VADD, zFWV_VSUB };

// enum fwvfmafunct6
enum zfwvfmafunct6 { zFWVF_VMACC, zFWVF_VNMACC, zFWVF_VMSAC, zFWVF_VNMSAC };

// enum fwvffunct6
enum zfwvffunct6 { zFWVF_VADD, zFWVF_VSUB, zFWVF_VMUL };

// enum fwffunct6
enum zfwffunct6 { zFWF_VADD, zFWF_VSUB };

// enum fvvmfunct6
enum zfvvmfunct6 { zFVVM_VMFEQ, zFVVM_VMFLE, zFVVM_VMFLT, zFVVM_VMFNE };

// enum fvvmafunct6
enum zfvvmafunct6 { zFVV_VMADD, zFVV_VNMADD, zFVV_VMSUB, zFVV_VNMSUB, zFVV_VMACC, zFVV_VNMACC, zFVV_VMSAC, zFVV_VNMSAC };

// enum fvvfunct6
enum zfvvfunct6 { zFVV_VADD, zFVV_VSUB, zFVV_VMIN, zFVV_VMAX, zFVV_VSGNJ, zFVV_VSGNJN, zFVV_VSGNJX, zFVV_VDIV, zFVV_VMUL };

// enum fvfmfunct6
enum zfvfmfunct6 { zVFM_VMFEQ, zVFM_VMFLE, zVFM_VMFLT, zVFM_VMFNE, zVFM_VMFGT, zVFM_VMFGE };

// enum fvfmafunct6
enum zfvfmafunct6 { zVF_VMADD, zVF_VNMADD, zVF_VMSUB, zVF_VNMSUB, zVF_VMACC, zVF_VNMACC, zVF_VMSAC, zVF_VNMSAC };

// enum fvffunct6
enum zfvffunct6 { zVF_VADD, zVF_VSUB, zVF_VMIN, zVF_VMAX, zVF_VSGNJ, zVF_VSGNJN, zVF_VSGNJX, zVF_VDIV, zVF_VRDIV, zVF_VMUL, zVF_VRSUB, zVF_VSLIDE1UP, zVF_VSLIDE1DOWN };

// enum extop_zbb
enum zextop_zzbb { zRISCV_SEXTB, zRISCV_SEXTH, zRISCV_ZEXTH };

// enum ext_ptw_sc
enum zext_ptw_sc { zPTW_SC_OK, zPTW_SC_TRAP };

// enum ext_ptw_lc
enum zext_ptw_lc { zPTW_LC_OK, zPTW_LC_CLEAR };

// enum ext_ptw_fail
enum zext_ptw_fail { zEPTWF_NO_PERM, zEPTWF_CAP_ERR };

// enum ext_ptw_error
enum zext_ptw_error { zAT_CAP_ERR };

// struct ext_ptw
struct zext_ptw {
  enum zext_ptw_lc zptw_lc;
  enum zext_ptw_sc zptw_sc;
};

// type abbreviation ext_exception
typedef unit zext_exception;

// enum ext_exc_type
enum zext_exc_type { zEXC_LOAD_CAP_PAGE_FAULT, zEXC_SAMO_CAP_PAGE_FAULT, zEXC_CHERI };

// enum ext_access_type
enum zext_access_type { zData, zCap };

// type abbreviation extPte
typedef uint64_t zextPte;

// union exception
enum kind_zexception { Kind_zError_internal_error, Kind_zError_not_implemented, Kind_zError_not_rv32e_register };

struct zexception {
  enum kind_zexception kind;
  union {
    struct { unit zError_internal_error; };
    struct { sail_string zError_not_implemented; };
    struct { unit zError_not_rv32e_register; };
  } variants;
};

// type abbreviation exc_code
typedef uint64_t zexc_code;

// enum csrop
enum zcsrop { zCSRRW, zCSRRS, zCSRRC };

// type abbreviation csreg
typedef uint64_t zcsreg;

// type abbreviation cregidx
typedef uint64_t zcregidx;

// struct ccsr
struct zccsr {uint64_t zbits;};

// type abbreviation capreg_idx
typedef uint64_t zcapreg_idx;

// enum cache_op_kind
enum zcache_op_kind { zCache_op_D_IVAC, zCache_op_D_ISW, zCache_op_D_CSW, zCache_op_D_CISW, zCache_op_D_ZVA, zCache_op_D_CVAC, zCache_op_D_CVAU, zCache_op_D_CIVAC, zCache_op_I_IALLUIS, zCache_op_I_IALLU, zCache_op_I_IVAU };

// enum bropw_zbb
enum zbropw_zzbb { zRISCV_ROLW, zRISCV_RORW };

// enum bropw_zba
enum zbropw_zzba { zRISCV_ADDUW, zRISCV_SH1ADDUW, zRISCV_SH2ADDUW, zRISCV_SH3ADDUW };

// enum brop_zbs
enum zbrop_zzbs { zRISCV_BCLR, zRISCV_BEXT, zRISCV_BINV, zRISCV_BSET };

// enum brop_zbkb
enum zbrop_zzbkb { zRISCV_PACK, zRISCV_PACKH };

// enum brop_zbb
enum zbrop_zzbb { zRISCV_ANDN, zRISCV_ORN, zRISCV_XNOR, zRISCV_MAX, zRISCV_MAXU, zRISCV_MIN, zRISCV_MINU, zRISCV_ROL, zRISCV_ROR };

// enum brop_zba
enum zbrop_zzba { zRISCV_SH1ADD, zRISCV_SH2ADD, zRISCV_SH3ADD };

// enum bop
enum zbop { zRISCV_BEQ, zRISCV_BNE, zRISCV_BLT, zRISCV_BGE, zRISCV_BLTU, zRISCV_BGEU };

// type abbreviation bit
typedef uint64_t zbit;

// enum biop_zbs
enum zbiop_zzbs { zRISCV_BCLRI, zRISCV_BEXTI, zRISCV_BINVI, zRISCV_BSETI };

// struct tuple_(%bv3, %bv3)
struct ztuple_z8z5bv3zCz0z5bv3z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv3, %bv8)
struct ztuple_z8z5bv3zCz0z5bv8z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv3, %bv10)
struct ztuple_z8z5bv3zCz0z5bv10z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv4, %bv4)
struct ztuple_z8z5bv4zCz0z5bv4z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bv5)
struct ztuple_z8z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bv10)
struct ztuple_z8z5bv5zCz0z5bv10z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv6, %bv3)
struct ztuple_z8z5bv6zCz0z5bv3z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv6, %bv5)
struct ztuple_z8z5bv6zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv8, %bv3)
struct ztuple_z8z5bv8zCz0z5bv3z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv20, %bv5)
struct ztuple_z8z5bv20zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv21, %bv5)
struct ztuple_z8z5bv21zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv3, %bv3, %bv9)
struct ztuple_z8z5bv3zCz0z5bv3zCz0z5bv9z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv5, %bv3, %bv3)
struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv5, %bv5, %enum zextop_zzbb)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzextop_zzzzbbz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zextop_zzbb ztup2;
};

// struct tuple_(%bv5, %bv5, %bv5)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv5, %bv5, %bv12)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv12z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv6, %bv5, %bv5)
struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv12, %bv5, %bv5)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv20, %bv5, %enum zuop)
struct ztuple_z8z5bv20zCz0z5bv5zCz0z5enumz0zzuopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zuop ztup2;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbrop_zzba)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbaz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbrop_zzba ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbrop_zzbb)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbbz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbrop_zzbb ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbrop_zzbkb)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbkbz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbrop_zzbkb ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbrop_zzbs)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbsz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbrop_zzbs ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbropw_zzba)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbaz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbropw_zzba ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zbropw_zzbb)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbbz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbropw_zzbb ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zrop)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zrop ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zropw)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropwz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zropw ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zsopw)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopwz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zsopw ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %bool)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  bool ztup3;
};

// struct tuple_(%bv6, %bv5, %bv5, %enum zbiop_zzbs)
struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbiop_zzzzbsz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbiop_zzbs ztup3;
};

// struct tuple_(%bv6, %bv5, %bv5, %enum zsop)
struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zsop ztup3;
};

// struct tuple_(%bv12, %bv5, %bv5, %enum ziop)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zziopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum ziop ztup3;
};

// struct tuple_(%bv13, %bv5, %bv5, %enum zbop)
struct ztuple_z8z5bv13zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbop ztup3;
};

// struct tuple_(%bv4, %bv4, %bv4, %bv5, %bv5)
struct ztuple_z8z5bv4zCz0z5bv4zCz0z5bv4zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%bv12, %bv5, %bv5, %bool, %enum zcsrop)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzcsropz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  bool ztup3;
  enum zcsrop ztup4;
};

// struct tuple_(%bv5, %bv5, %bv5, %bool, %bool, %bool)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5boolzCz0z5boolz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  bool ztup3;
  bool ztup4;
  bool ztup5;
};

// struct tuple_(%bv12, %bv5, %bv5, %enum zword_width, %bool, %bool)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zword_width ztup3;
  bool ztup4;
  bool ztup5;
};

// struct tuple_(%bv12, %bv5, %bv5, %bool, %enum zword_width, %bool, %bool)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  bool ztup3;
  enum zword_width ztup4;
  bool ztup5;
  bool ztup6;
};

// union ast
enum kind_zast { Kind_zADDIW, Kind_zAUICGP, Kind_zAUIPCC, Kind_zBTYPE, Kind_zCAndPerm, Kind_zCClearTag, Kind_zCGetAddr, Kind_zCGetBase, Kind_zCGetHigh, Kind_zCGetLen, Kind_zCGetPerm, Kind_zCGetTag, Kind_zCGetTop, Kind_zCGetType, Kind_zCIncAddr, Kind_zCIncAddrImmediate, Kind_zCJAL, Kind_zCJALR, Kind_zCMove, Kind_zCRAM, Kind_zCRRL, Kind_zCSEQX, Kind_zCSR, Kind_zCSeal, Kind_zCSetAddr, Kind_zCSetBounds, Kind_zCSetBoundsExact, Kind_zCSetBoundsImmediate, Kind_zCSetBoundsRoundDown, Kind_zCSetHigh, Kind_zCSpecialRW, Kind_zCSub, Kind_zCTestSubset, Kind_zCUnseal, Kind_zC_ADD, Kind_zC_ADDI, Kind_zC_ADDI16SP, Kind_zC_ADDI4SPN, Kind_zC_ADDIW, Kind_zC_ADDI_HINT, Kind_zC_ADDW, Kind_zC_ADD_HINT, Kind_zC_AND, Kind_zC_ANDI, Kind_zC_BEQZ, Kind_zC_BNEZ, Kind_zC_CIncAddr16CSP, Kind_zC_CIncAddr4CSPN, Kind_zC_CJAL, Kind_zC_CJALR, Kind_zC_CJR, Kind_zC_CLC, Kind_zC_CLCSP, Kind_zC_CSC, Kind_zC_CSCSP, Kind_zC_EBREAK, Kind_zC_ILLEGAL, Kind_zC_J, Kind_zC_JAL, Kind_zC_JALR, Kind_zC_JR, Kind_zC_LD, Kind_zC_LDSP, Kind_zC_LI, Kind_zC_LI_HINT, Kind_zC_LUI, Kind_zC_LUI_HINT, Kind_zC_LW, Kind_zC_LWSP, Kind_zC_MV, Kind_zC_MV_HINT, Kind_zC_NOP, Kind_zC_NOP_HINT, Kind_zC_OR, Kind_zC_SD, Kind_zC_SDSP, Kind_zC_SLLI, Kind_zC_SLLI_HINT, Kind_zC_SRAI, Kind_zC_SRAI_HINT, Kind_zC_SRLI, Kind_zC_SRLI_HINT, Kind_zC_SUB, Kind_zC_SUBW, Kind_zC_SW, Kind_zC_SWSP, Kind_zC_XOR, Kind_zDIV, Kind_zDIVW, Kind_zEBREAK, Kind_zECALL, Kind_zFENCE, Kind_zFENCEI, Kind_zFENCEI_RESERVED, Kind_zFENCE_RESERVED, Kind_zFENCE_TSO, Kind_zILLEGAL, Kind_zITYPE, Kind_zLOAD, Kind_zLoadCapImm, Kind_zMRET, Kind_zMUL, Kind_zMULW, Kind_zNOT_CAPMODE, Kind_zNOT_C_CAPMODE, Kind_zREM, Kind_zREMW, Kind_zRISCV_BREV8, Kind_zRISCV_CLMUL, Kind_zRISCV_CLMULH, Kind_zRISCV_CLMULR, Kind_zRISCV_CLZ, Kind_zRISCV_CLZW, Kind_zRISCV_CPOP, Kind_zRISCV_CPOPW, Kind_zRISCV_CTZ, Kind_zRISCV_CTZW, Kind_zRISCV_JAL, Kind_zRISCV_JALR, Kind_zRISCV_ORCB, Kind_zRISCV_REV8, Kind_zRISCV_RORI, Kind_zRISCV_RORIW, Kind_zRISCV_SLLIUW, Kind_zRISCV_UNZIP, Kind_zRISCV_XPERM4, Kind_zRISCV_XPERM8, Kind_zRISCV_ZIP, Kind_zRTYPE, Kind_zRTYPEW, Kind_zSFENCE_VMA, Kind_zSHIFTIOP, Kind_zSHIFTIWOP, Kind_zSRET, Kind_zSTORE, Kind_zStoreCapImm, Kind_zUTYPE, Kind_zWFI, Kind_zZBA_RTYPE, Kind_zZBA_RTYPEUW, Kind_zZBB_EXTOP, Kind_zZBB_RTYPE, Kind_zZBB_RTYPEW, Kind_zZBKB_PACKW, Kind_zZBKB_RTYPE, Kind_zZBS_IOP, Kind_zZBS_RTYPE };

struct zast {
  enum kind_zast kind;
  union {
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 zADDIW; };
    struct { struct ztuple_z8z5bv20zCz0z5bv5z9 zAUICGP; };
    struct { struct ztuple_z8z5bv20zCz0z5bv5z9 zAUIPCC; };
    struct { struct ztuple_z8z5bv13zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbopz9 zBTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCAndPerm; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCClearTag; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetAddr; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetBase; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetHigh; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetLen; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetPerm; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetTag; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetTop; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCGetType; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCIncAddr; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv12z9 zCIncAddrImmediate; };
    struct { struct ztuple_z8z5bv21zCz0z5bv5z9 zCJAL; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 zCJALR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCMove; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCRAM; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zCRRL; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSEQX; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzcsropz9 zCSR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSeal; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSetAddr; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSetBounds; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSetBoundsExact; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv12z9 zCSetBoundsImmediate; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSetBoundsRoundDown; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSetHigh; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSpecialRW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCSub; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCTestSubset; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zCUnseal; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zC_ADD; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_ADDI; };
    struct { uint64_t zC_ADDI16SP; };
    struct { struct ztuple_z8z5bv3zCz0z5bv8z9 zC_ADDI4SPN; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_ADDIW; };
    struct { uint64_t zC_ADDI_HINT; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_ADDW; };
    struct { uint64_t zC_ADD_HINT; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_AND; };
    struct { struct ztuple_z8z5bv6zCz0z5bv3z9 zC_ANDI; };
    struct { struct ztuple_z8z5bv8zCz0z5bv3z9 zC_BEQZ; };
    struct { struct ztuple_z8z5bv8zCz0z5bv3z9 zC_BNEZ; };
    struct { uint64_t zC_CIncAddr16CSP; };
    struct { struct ztuple_z8z5bv3zCz0z5bv10z9 zC_CIncAddr4CSPN; };
    struct { uint64_t zC_CJAL; };
    struct { uint64_t zC_CJALR; };
    struct { uint64_t zC_CJR; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3zCz0z5bv9z9 zC_CLC; };
    struct { struct ztuple_z8z5bv5zCz0z5bv10z9 zC_CLCSP; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3zCz0z5bv9z9 zC_CSC; };
    struct { struct ztuple_z8z5bv5zCz0z5bv10z9 zC_CSCSP; };
    struct { unit zC_EBREAK; };
    struct { uint64_t zC_ILLEGAL; };
    struct { uint64_t zC_J; };
    struct { uint64_t zC_JAL; };
    struct { uint64_t zC_JALR; };
    struct { uint64_t zC_JR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_LD; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_LDSP; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_LI; };
    struct { uint64_t zC_LI_HINT; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_LUI; };
    struct { uint64_t zC_LUI_HINT; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_LW; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_LWSP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zC_MV; };
    struct { uint64_t zC_MV_HINT; };
    struct { unit zC_NOP; };
    struct { uint64_t zC_NOP_HINT; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_OR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_SD; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_SDSP; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_SLLI; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_SLLI_HINT; };
    struct { struct ztuple_z8z5bv6zCz0z5bv3z9 zC_SRAI; };
    struct { uint64_t zC_SRAI_HINT; };
    struct { struct ztuple_z8z5bv6zCz0z5bv3z9 zC_SRLI; };
    struct { uint64_t zC_SRLI_HINT; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_SUB; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_SUBW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_SW; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_SWSP; };
    struct { struct ztuple_z8z5bv3zCz0z5bv3z9 zC_XOR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zDIV; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zDIVW; };
    struct { unit zEBREAK; };
    struct { unit zECALL; };
    struct { struct ztuple_z8z5bv4zCz0z5bv4z9 zFENCE; };
    struct { unit zFENCEI; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 zFENCEI_RESERVED; };
    struct { struct ztuple_z8z5bv4zCz0z5bv4zCz0z5bv4zCz0z5bv5zCz0z5bv5z9 zFENCE_RESERVED; };
    struct { struct ztuple_z8z5bv4zCz0z5bv4z9 zFENCE_TSO; };
    struct { uint64_t zILLEGAL; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zziopz9 zITYPE; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 zLOAD; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv12z9 zLoadCapImm; };
    struct { unit zMRET; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5boolzCz0z5boolz9 zMUL; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMULW; };
    struct { uint64_t zNOT_CAPMODE; };
    struct { uint64_t zNOT_C_CAPMODE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zREM; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zREMW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_BREV8; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_CLMUL; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_CLMULH; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_CLMULR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CLZ; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CLZW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CPOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CPOPW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CTZ; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_CTZW; };
    struct { struct ztuple_z8z5bv21zCz0z5bv5z9 zRISCV_JAL; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 zRISCV_JALR; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_ORCB; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_REV8; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5z9 zRISCV_RORI; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_RORIW; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5z9 zRISCV_SLLIUW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_UNZIP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_XPERM4; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_XPERM8; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_ZIP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropz9 zRTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropwz9 zRTYPEW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSFENCE_VMA; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopz9 zSHIFTIOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopwz9 zSHIFTIWOP; };
    struct { unit zSRET; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 zSTORE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv12z9 zStoreCapImm; };
    struct { struct ztuple_z8z5bv20zCz0z5bv5zCz0z5enumz0zzuopz9 zUTYPE; };
    struct { unit zWFI; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbaz9 zZBA_RTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbaz9 zZBA_RTYPEUW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzextop_zzzzbbz9 zZBB_EXTOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbbz9 zZBB_RTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbbz9 zZBB_RTYPEW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zZBKB_PACKW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbkbz9 zZBKB_RTYPE; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbiop_zzzzbsz9 zZBS_IOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbsz9 zZBS_RTYPE; };
  } variants;
};

// union option<Uast>
enum kind_zoptionzIUastzK { Kind_zNonezIUastzK, Kind_zSomezIUastzK };

struct zoptionzIUastzK {
  enum kind_zoptionzIUastzK kind;
  union {
    struct { unit zNonezIUastzK; };
    struct { struct zast zSomezIUastzK; };
  } variants;
};

// type abbreviation asid32
typedef uint64_t zasid32;

// type abbreviation arch_xlen
typedef uint64_t zarch_xlen;

// enum amoop
enum zamoop { zAMOSWAP, zAMOADD, zAMOXOR, zAMOAND, zAMOOR, zAMOMIN, zAMOMAX, zAMOMINU, zAMOMAXU };

// enum agtype
enum zagtype { zUNDISTURBED, zAGNOSTIC };

// enum a64_barrier_type
enum za64_barrier_type { zA64_barrier_all, zA64_barrier_LD, zA64_barrier_ST };

// enum a64_barrier_domain
enum za64_barrier_domain { zA64_FullShare, zA64_InnerShare, zA64_OuterShare, zA64_NonShare };

// struct tuple_(%enum za64_barrier_domain, %enum za64_barrier_type)
struct ztuple_z8z5enumz0zza64_barrier_domainzCz0z5enumz0zza64_barrier_typez9 {
  enum za64_barrier_domain ztup0;
  enum za64_barrier_type ztup1;
};

// union barrier_kind
enum kind_zbarrier_kind { Kind_zBarrier_DMB, Kind_zBarrier_DSB, Kind_zBarrier_Eieio, Kind_zBarrier_ISB, Kind_zBarrier_Isync, Kind_zBarrier_LwSync, Kind_zBarrier_MIPS_SYNC, Kind_zBarrier_RISCV_i, Kind_zBarrier_RISCV_r_r, Kind_zBarrier_RISCV_r_rw, Kind_zBarrier_RISCV_r_w, Kind_zBarrier_RISCV_rw_r, Kind_zBarrier_RISCV_rw_rw, Kind_zBarrier_RISCV_rw_w, Kind_zBarrier_RISCV_tso, Kind_zBarrier_RISCV_w_r, Kind_zBarrier_RISCV_w_rw, Kind_zBarrier_RISCV_w_w, Kind_zBarrier_Sync, Kind_zBarrier_x86_MFENCE };

struct zbarrier_kind {
  enum kind_zbarrier_kind kind;
  union {
    struct { struct ztuple_z8z5enumz0zza64_barrier_domainzCz0z5enumz0zza64_barrier_typez9 zBarrier_DMB; };
    struct { struct ztuple_z8z5enumz0zza64_barrier_domainzCz0z5enumz0zza64_barrier_typez9 zBarrier_DSB; };
    struct { unit zBarrier_Eieio; };
    struct { unit zBarrier_ISB; };
    struct { unit zBarrier_Isync; };
    struct { unit zBarrier_LwSync; };
    struct { unit zBarrier_MIPS_SYNC; };
    struct { unit zBarrier_RISCV_i; };
    struct { unit zBarrier_RISCV_r_r; };
    struct { unit zBarrier_RISCV_r_rw; };
    struct { unit zBarrier_RISCV_r_w; };
    struct { unit zBarrier_RISCV_rw_r; };
    struct { unit zBarrier_RISCV_rw_rw; };
    struct { unit zBarrier_RISCV_rw_w; };
    struct { unit zBarrier_RISCV_tso; };
    struct { unit zBarrier_RISCV_w_r; };
    struct { unit zBarrier_RISCV_w_rw; };
    struct { unit zBarrier_RISCV_w_w; };
    struct { unit zBarrier_Sync; };
    struct { unit zBarrier_x86_MFENCE; };
  } variants;
};

// struct Vtype
struct zVtype {uint64_t zbits;};

// struct Vcsr
struct zVcsr {uint64_t zbits;};

// struct Ustatus
struct zUstatus {uint64_t zbits;};

// struct Uinterrupts
struct zUinterrupts {uint64_t zbits;};

// enum TrapVectorMode
enum zTrapVectorMode { zTV_Direct, zTV_Vector, zTV_Reserved };

// struct TLB_Entry
struct zTLB_Entry {
  uint64_t zage;
  lbits zasid;
  bool zglobal;
  lbits zpAddr;
  lbits zpte;
  lbits zpteAddr;
  lbits zvAddr;
  lbits zvAddrMask;
  lbits zvMatchMask;
};

// union option<RTLB_Entry>
enum kind_zoptionzIRTLB_EntryzK { Kind_zNonezIRTLB_EntryzK, Kind_zSomezIRTLB_EntryzK };

struct zoptionzIRTLB_EntryzK {
  enum kind_zoptionzIRTLB_EntryzK kind;
  union {
    struct { unit zNonezIRTLB_EntryzK; };
    struct { struct zTLB_Entry zSomezIRTLB_EntryzK; };
  } variants;
};

// struct tuple_(%i, %struct zTLB_Entry)
struct ztuple_z8z5izCz0z5structz0zzTLB_Entryz9 {
  sail_int ztup0;
  struct zTLB_Entry ztup1;
};

// union option<(i,RTLB_Entry)>
enum kind_zoptionzIz8izCRTLB_Entryz9zK { Kind_zNonezIz8izCRTLB_Entryz9zK, Kind_zSomezIz8izCRTLB_Entryz9zK };

struct zoptionzIz8izCRTLB_Entryz9zK {
  enum kind_zoptionzIz8izCRTLB_Entryz9zK kind;
  union {
    struct { unit zNonezIz8izCRTLB_Entryz9zK; };
    struct { struct ztuple_z8z5izCz0z5structz0zzTLB_Entryz9 zSomezIz8izCRTLB_Entryz9zK; };
  } variants;
};

// type abbreviation TLB32_Entry
typedef struct zTLB_Entry zTLB32_Entry;

// struct Sstatus
struct zSstatus {uint64_t zbits;};

// struct Sinterrupts
struct zSinterrupts {uint64_t zbits;};

// struct Sedeleg
struct zSedeleg {uint64_t zbits;};

// struct Satp32
struct zSatp32 {uint64_t zbits;};

// struct SV32_Vaddr
struct zSV32_Vaddr {uint64_t zbits;};

// struct SV32_PTE
struct zSV32_PTE {uint64_t zbits;};

// enum SATPMode
enum zSATPMode { zSbare, zSv32, zSv39, zSv48 };

// enum Retired
enum zRetired { zRETIRE_SUCCESS, zRETIRE_FAIL };

// struct RVFI_DII_Instruction_Packet
struct zRVFI_DII_Instruction_Packet {uint64_t zbits;};

// struct RVFI_DII_Execution_Packet_V1
struct zRVFI_DII_Execution_Packet_V1 {lbits zbits;};

// struct RVFI_DII_Execution_Packet_PC
struct zRVFI_DII_Execution_Packet_PC {lbits zbits;};

// struct RVFI_DII_Execution_Packet_InstMetaData
struct zRVFI_DII_Execution_Packet_InstMetaData {lbits zbits;};

// struct RVFI_DII_Execution_Packet_Ext_MemAccess
struct zRVFI_DII_Execution_Packet_Ext_MemAccess {lbits zbits;};

// struct RVFI_DII_Execution_Packet_Ext_Integer
struct zRVFI_DII_Execution_Packet_Ext_Integer {lbits zbits;};

// struct RVFI_DII_Execution_Packet_Ext_CSR
struct zRVFI_DII_Execution_Packet_Ext_CSR {lbits zbits;};

// struct RVFI_DII_Execution_Packet_Ext_CHERI_SCR
struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR {lbits zbits;};

// struct RVFI_DII_Execution_Packet_Ext_CHERI
struct zRVFI_DII_Execution_Packet_Ext_CHERI {lbits zbits;};

// struct RVFI_DII_Execution_PacketV2
struct zRVFI_DII_Execution_PacketV2 {lbits zbits;};

// enum Privilege
enum zPrivilege { zUser, zSupervisor, zMachine };

// struct tuple_(%bv, %enum zPrivilege)
struct ztuple_z8z5bvzCz0z5enumz0zzPrivilegez9 {
  lbits ztup0;
  enum zPrivilege ztup1;
};

// union option<(b,EPrivilege%)>
enum kind_zoptionzIz8bzCEPrivilegez5z9zK { Kind_zNonezIz8bzCEPrivilegez5z9zK, Kind_zSomezIz8bzCEPrivilegez5z9zK };

struct zoptionzIz8bzCEPrivilegez5z9zK {
  enum kind_zoptionzIz8bzCEPrivilegez5z9zK kind;
  union {
    struct { unit zNonezIz8bzCEPrivilegez5z9zK; };
    struct { struct ztuple_z8z5bvzCz0z5enumz0zzPrivilegez9 zSomezIz8bzCEPrivilegez5z9zK; };
  } variants;
};

// struct Pmpcfg_ent
struct zPmpcfg_ent {uint64_t zbits;};

// enum PmpAddrMatchType
enum zPmpAddrMatchType { zOFF, zTOR, zNA4, zNAPOT };

// union PTW_Error
enum kind_zPTW_Error { Kind_zPTW_Access, Kind_zPTW_Ext_Error, Kind_zPTW_Invalid_Addr, Kind_zPTW_Invalid_PTE, Kind_zPTW_Misaligned, Kind_zPTW_No_Permission, Kind_zPTW_PTE_Update };

struct zPTW_Error {
  enum kind_zPTW_Error kind;
  union {
    struct { unit zPTW_Access; };
    struct { enum zext_ptw_error zPTW_Ext_Error; };
    struct { unit zPTW_Invalid_Addr; };
    struct { unit zPTW_Invalid_PTE; };
    struct { unit zPTW_Misaligned; };
    struct { unit zPTW_No_Permission; };
    struct { unit zPTW_PTE_Update; };
  } variants;
};

// struct tuple_(%union zPTW_Error, %struct zext_ptw)
struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5structz0zzext_ptwz9 {
  struct zPTW_Error ztup0;
  struct zext_ptw ztup1;
};

// struct tuple_(%bv, %struct zext_ptw)
struct ztuple_z8z5bvzCz0z5structz0zzext_ptwz9 {
  lbits ztup0;
  struct zext_ptw ztup1;
};

// union TR_Result<b,UPTW_Error>
enum kind_zTR_ResultzIbzCUPTW_ErrorzK { Kind_zTR_AddresszIbzCUPTW_ErrorzK, Kind_zTR_FailurezIbzCUPTW_ErrorzK };

struct zTR_ResultzIbzCUPTW_ErrorzK {
  enum kind_zTR_ResultzIbzCUPTW_ErrorzK kind;
  union {
    struct { struct ztuple_z8z5bvzCz0z5structz0zzext_ptwz9 zTR_AddresszIbzCUPTW_ErrorzK; };
    struct { struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5structz0zzext_ptwz9 zTR_FailurezIbzCUPTW_ErrorzK; };
  } variants;
};

// struct tuple_(%bv, %struct zSV32_PTE, %bv, %i, %bool, %struct zext_ptw)
struct ztuple_z8z5bvzCz0z5structz0zzSV32_PTEzCz0z5bvzCz0z5izCz0z5boolzCz0z5structz0zzext_ptwz9 {
  lbits ztup0;
  struct zSV32_PTE ztup1;
  lbits ztup2;
  sail_int ztup3;
  bool ztup4;
  struct zext_ptw ztup5;
};

// union PTW_Result<b,RSV32_PTE>
enum kind_zPTW_ResultzIbzCRSV32_PTEzK { Kind_zPTW_FailurezIbzCRSV32_PTEzK, Kind_zPTW_SuccesszIbzCRSV32_PTEzK };

struct zPTW_ResultzIbzCRSV32_PTEzK {
  enum kind_zPTW_ResultzIbzCRSV32_PTEzK kind;
  union {
    struct { struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5structz0zzext_ptwz9 zPTW_FailurezIbzCRSV32_PTEzK; };
    struct { struct ztuple_z8z5bvzCz0z5structz0zzSV32_PTEzCz0z5bvzCz0z5izCz0z5boolzCz0z5structz0zzext_ptwz9 zPTW_SuccesszIbzCRSV32_PTEzK; };
  } variants;
};

// struct tuple_(%struct zext_ptw, %enum zext_ptw_fail)
struct ztuple_z8z5structz0zzext_ptwzCz0z5enumz0zzext_ptw_failz9 {
  struct zext_ptw ztup0;
  enum zext_ptw_fail ztup1;
};

// union PTE_Check
enum kind_zPTE_Check { Kind_zPTE_Check_Failure, Kind_zPTE_Check_Success };

struct zPTE_Check {
  enum kind_zPTE_Check kind;
  union {
    struct { struct ztuple_z8z5structz0zzext_ptwzCz0z5enumz0zzext_ptw_failz9 zPTE_Check_Failure; };
    struct { struct zext_ptw zPTE_Check_Success; };
  } variants;
};

// struct PTE_Bits
struct zPTE_Bits {uint64_t zbits;};

// struct tuple_(%struct zPTE_Bits, %bv)
struct ztuple_z8z5structz0zzPTE_BitszCz0z5bvz9 {
  struct zPTE_Bits ztup0;
  lbits ztup1;
};

// union option<(RPTE_Bits,b)>
enum kind_zoptionzIz8RPTE_BitszCbz9zK { Kind_zNonezIz8RPTE_BitszCbz9zK, Kind_zSomezIz8RPTE_BitszCbz9zK };

struct zoptionzIz8RPTE_BitszCbz9zK {
  enum kind_zoptionzIz8RPTE_BitszCbz9zK kind;
  union {
    struct { unit zNonezIz8RPTE_BitszCbz9zK; };
    struct { struct ztuple_z8z5structz0zzPTE_BitszCz0z5bvz9 zSomezIz8RPTE_BitszCbz9zK; };
  } variants;
};

// struct Mtvec
struct zMtvec {uint64_t zbits;};

// struct Mstatush
struct zMstatush {uint64_t zbits;};

// struct Mstatus
struct zMstatus {uint64_t zbits;};

// struct Misa
struct zMisa {uint64_t zbits;};

// struct Minterrupts
struct zMinterrupts {uint64_t zbits;};

// struct Medeleg
struct zMedeleg {uint64_t zbits;};

// struct Mcause
struct zMcause {uint64_t zbits;};

// enum InterruptType
enum zInterruptType { zI_U_Software, zI_S_Software, zI_M_Software, zI_U_Timer, zI_S_Timer, zI_M_Timer, zI_U_External, zI_S_External, zI_M_External };

// union option<EInterruptType%>
enum kind_zoptionzIEInterruptTypez5zK { Kind_zNonezIEInterruptTypez5zK, Kind_zSomezIEInterruptTypez5zK };

struct zoptionzIEInterruptTypez5zK {
  enum kind_zoptionzIEInterruptTypez5zK kind;
  union {
    struct { unit zNonezIEInterruptTypez5zK; };
    struct { enum zInterruptType zSomezIEInterruptTypez5zK; };
  } variants;
};

// struct tuple_(%enum zInterruptType, %enum zPrivilege)
struct ztuple_z8z5enumz0zzInterruptTypezCz0z5enumz0zzPrivilegez9 {
  enum zInterruptType ztup0;
  enum zPrivilege ztup1;
};

// union option<(EInterruptType%,EPrivilege%)>
enum kind_zoptionzIz8EInterruptTypez5zCEPrivilegez5z9zK { Kind_zNonezIz8EInterruptTypez5zCEPrivilegez5z9zK, Kind_zSomezIz8EInterruptTypez5zCEPrivilegez5z9zK };

struct zoptionzIz8EInterruptTypez5zCEPrivilegez5z9zK {
  enum kind_zoptionzIz8EInterruptTypez5zCEPrivilegez5z9zK kind;
  union {
    struct { unit zNonezIz8EInterruptTypez5zCEPrivilegez5z9zK; };
    struct { struct ztuple_z8z5enumz0zzInterruptTypezCz0z5enumz0zzPrivilegez9 zSomezIz8EInterruptTypez5zCEPrivilegez5z9zK; };
  } variants;
};

// struct Ext_PTE_Bits
struct zExt_PTE_Bits {uint64_t zbits;};

// enum ExtStatus
enum zExtStatus { zOff, zInitial, zClean, zDirty };

// union ExceptionType
enum kind_zExceptionType { Kind_zE_Breakpoint, Kind_zE_Extension, Kind_zE_Fetch_Access_Fault, Kind_zE_Fetch_Addr_Align, Kind_zE_Fetch_Page_Fault, Kind_zE_Illegal_Instr, Kind_zE_Load_Access_Fault, Kind_zE_Load_Addr_Align, Kind_zE_Load_Page_Fault, Kind_zE_M_EnvCall, Kind_zE_Reserved_10, Kind_zE_Reserved_14, Kind_zE_SAMO_Access_Fault, Kind_zE_SAMO_Addr_Align, Kind_zE_SAMO_Page_Fault, Kind_zE_S_EnvCall, Kind_zE_U_EnvCall };

struct zExceptionType {
  enum kind_zExceptionType kind;
  union {
    struct { unit zE_Breakpoint; };
    struct { enum zext_exc_type zE_Extension; };
    struct { unit zE_Fetch_Access_Fault; };
    struct { unit zE_Fetch_Addr_Align; };
    struct { unit zE_Fetch_Page_Fault; };
    struct { unit zE_Illegal_Instr; };
    struct { unit zE_Load_Access_Fault; };
    struct { unit zE_Load_Addr_Align; };
    struct { unit zE_Load_Page_Fault; };
    struct { unit zE_M_EnvCall; };
    struct { unit zE_Reserved_10; };
    struct { unit zE_Reserved_14; };
    struct { unit zE_SAMO_Access_Fault; };
    struct { unit zE_SAMO_Addr_Align; };
    struct { unit zE_SAMO_Page_Fault; };
    struct { unit zE_S_EnvCall; };
    struct { unit zE_U_EnvCall; };
  } variants;
};

// struct sync_exception
struct zsync_exception {
  struct zoptionzIbzK zexcinfo;
  struct zoptionzIuzK zext;
  struct zExceptionType ztrap;
};

// union ctl_result
enum kind_zctl_result { Kind_zCTL_MRET, Kind_zCTL_SRET, Kind_zCTL_TRAP, Kind_zCTL_URET };

struct zctl_result {
  enum kind_zctl_result kind;
  union {
    struct { unit zCTL_MRET; };
    struct { unit zCTL_SRET; };
    struct { struct zsync_exception zCTL_TRAP; };
    struct { unit zCTL_URET; };
  } variants;
};

// union option<UExceptionType>
enum kind_zoptionzIUExceptionTypezK { Kind_zNonezIUExceptionTypezK, Kind_zSomezIUExceptionTypezK };

struct zoptionzIUExceptionTypezK {
  enum kind_zoptionzIUExceptionTypezK kind;
  union {
    struct { unit zNonezIUExceptionTypezK; };
    struct { struct zExceptionType zSomezIUExceptionTypezK; };
  } variants;
};

// struct tuple_(%union zExceptionType, %struct zext_ptw)
struct ztuple_z8z5unionz0zzExceptionTypezCz0z5structz0zzext_ptwz9 {
  struct zExceptionType ztup0;
  struct zext_ptw ztup1;
};

// union TR_Result<b,UExceptionType>
enum kind_zTR_ResultzIbzCUExceptionTypezK { Kind_zTR_AddresszIbzCUExceptionTypezK, Kind_zTR_FailurezIbzCUExceptionTypezK };

struct zTR_ResultzIbzCUExceptionTypezK {
  enum kind_zTR_ResultzIbzCUExceptionTypezK kind;
  union {
    struct { struct ztuple_z8z5bvzCz0z5structz0zzext_ptwz9 zTR_AddresszIbzCUExceptionTypezK; };
    struct { struct ztuple_z8z5unionz0zzExceptionTypezCz0z5structz0zzext_ptwz9 zTR_FailurezIbzCUExceptionTypezK; };
  } variants;
};

// union MemoryOpResult<u>
enum kind_zMemoryOpResultzIuzK { Kind_zMemExceptionzIuzK, Kind_zMemValuezIuzK };

struct zMemoryOpResultzIuzK {
  enum kind_zMemoryOpResultzIuzK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIuzK; };
    struct { unit zMemValuezIuzK; };
  } variants;
};

// union MemoryOpResult<o>
enum kind_zMemoryOpResultzIozK { Kind_zMemExceptionzIozK, Kind_zMemValuezIozK };

struct zMemoryOpResultzIozK {
  enum kind_zMemoryOpResultzIozK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIozK; };
    struct { bool zMemValuezIozK; };
  } variants;
};

// union MemoryOpResult<b>
enum kind_zMemoryOpResultzIbzK { Kind_zMemExceptionzIbzK, Kind_zMemValuezIbzK };

struct zMemoryOpResultzIbzK {
  enum kind_zMemoryOpResultzIbzK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIbzK; };
    struct { lbits zMemValuezIbzK; };
  } variants;
};

// union MemoryOpResult<(b,o)>
enum kind_zMemoryOpResultzIz8bzCoz9zK { Kind_zMemExceptionzIz8bzCoz9zK, Kind_zMemValuezIz8bzCoz9zK };

struct zMemoryOpResultzIz8bzCoz9zK {
  enum kind_zMemoryOpResultzIz8bzCoz9zK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIz8bzCoz9zK; };
    struct { struct ztuple_z8z5bvzCz0z5boolz9 zMemValuezIz8bzCoz9zK; };
  } variants;
};

// union Ext_PhysAddr_Check
enum kind_zExt_PhysAddr_Check { Kind_zExt_PhysAddr_Error, Kind_zExt_PhysAddr_OK };

struct zExt_PhysAddr_Check {
  enum kind_zExt_PhysAddr_Check kind;
  union {
    struct { struct zExceptionType zExt_PhysAddr_Error; };
    struct { unit zExt_PhysAddr_OK; };
  } variants;
};

// struct Envcfg
struct zEnvcfg {uint64_t zbits;};

// struct EncCapability
struct zEncCapability {
  uint64_t zB;
  uint64_t zT;
  uint64_t zaddress;
  uint64_t zcE;
  uint64_t zcotype;
  uint64_t zcperms;
  uint64_t zreserved;
};

// struct Counterin
struct zCounterin {uint64_t zbits;};

// struct Counteren
struct zCounteren {uint64_t zbits;};

// enum ClearRegSet
enum zClearRegSet { zGPRegs, zFPRegs };

// struct Capability
struct zCapability {
  uint64_t zB;
  uint64_t zE;
  uint64_t zT;
  bool zaccess_system_regs;
  uint64_t zaddress;
  bool zglobal;
  uint64_t zotype;
  bool zperm_user0;
  bool zpermit_execute;
  bool zpermit_load;
  bool zpermit_load_global;
  bool zpermit_load_mutable;
  bool zpermit_load_store_cap;
  bool zpermit_seal;
  bool zpermit_store;
  bool zpermit_store_local_cap;
  bool zpermit_unseal;
  uint64_t zreserved;
  bool ztag;
};

// type abbreviation regtype
typedef struct zCapability zregtype;

// union MemoryOpResult<RCapability>
enum kind_zMemoryOpResultzIRCapabilityzK { Kind_zMemExceptionzIRCapabilityzK, Kind_zMemValuezIRCapabilityzK };

struct zMemoryOpResultzIRCapabilityzK {
  enum kind_zMemoryOpResultzIRCapabilityzK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIRCapabilityzK; };
    struct { struct zCapability zMemValuezIRCapabilityzK; };
  } variants;
};

// type abbreviation CapPermsBits
typedef uint64_t zCapPermsBits;

// type abbreviation CapLenBits
typedef uint64_t zCapLenBits;

// enum CapEx
enum zCapEx { zCapEx_None, zCapEx_BoundsViolation, zCapEx_TagViolation, zCapEx_SealViolation, zCapEx_TypeViolation, zCapEx_UserDefViolation, zCapEx_UnalignedBase, zCapEx_GlobalViolation, zCapEx_PermitExecuteViolation, zCapEx_PermitLoadViolation, zCapEx_PermitStoreViolation, zCapEx_PermitLoadCapViolation, zCapEx_PermitStoreCapViolation, zCapEx_AccessSystemRegsViolation, zCapEx_PermitCInvokeViolation, zCapEx_PermitSetCIDViolation };

// type abbreviation ext_fetch_addr_error
typedef enum zCapEx zext_fetch_addr_error;

// struct tuple_(%enum zCapEx, %bv6)
struct ztuple_z8z5enumz0zzCapExzCz0z5bv6z9 {
  enum zCapEx ztup0;
  uint64_t ztup1;
};

// type abbreviation ext_data_addr_error
typedef struct ztuple_z8z5enumz0zzCapExzCz0z5bv6z9 zext_data_addr_error;

// type abbreviation ext_control_addr_error
typedef struct ztuple_z8z5enumz0zzCapExzCz0z5bv6z9 zext_control_addr_error;

// struct tuple_(%union zExceptionType, %bv32)
struct ztuple_z8z5unionz0zzExceptionTypezCz0z5bv32z9 {
  struct zExceptionType ztup0;
  uint64_t ztup1;
};

// union FetchResult
enum kind_zFetchResult { Kind_zF_Base, Kind_zF_Error, Kind_zF_Ext_Error, Kind_zF_RVC };

struct zFetchResult {
  enum kind_zFetchResult kind;
  union {
    struct { uint64_t zF_Base; };
    struct { struct ztuple_z8z5unionz0zzExceptionTypezCz0z5bv32z9 zF_Error; };
    struct { enum zCapEx zF_Ext_Error; };
    struct { uint64_t zF_RVC; };
  } variants;
};

// union Ext_FetchAddr_Check<ECapEx%>
enum kind_zExt_FetchAddr_CheckzIECapExz5zK { Kind_zExt_FetchAddr_ErrorzIECapExz5zK, Kind_zExt_FetchAddr_OKzIECapExz5zK };

struct zExt_FetchAddr_CheckzIECapExz5zK {
  enum kind_zExt_FetchAddr_CheckzIECapExz5zK kind;
  union {
    struct { enum zCapEx zExt_FetchAddr_ErrorzIECapExz5zK; };
    struct { uint64_t zExt_FetchAddr_OKzIECapExz5zK; };
  } variants;
};

// struct tuple_(%enum zCapEx, %bv)
struct ztuple_z8z5enumz0zzCapExzCz0z5bvz9 {
  enum zCapEx ztup0;
  lbits ztup1;
};

// union Ext_DataAddr_Check<(ECapEx%,b)>
enum kind_zExt_DataAddr_CheckzIz8ECapExz5zCbz9zK { Kind_zExt_DataAddr_ErrorzIz8ECapExz5zCbz9zK, Kind_zExt_DataAddr_OKzIz8ECapExz5zCbz9zK };

struct zExt_DataAddr_CheckzIz8ECapExz5zCbz9zK {
  enum kind_zExt_DataAddr_CheckzIz8ECapExz5zCbz9zK kind;
  union {
    struct { struct ztuple_z8z5enumz0zzCapExzCz0z5bvz9 zExt_DataAddr_ErrorzIz8ECapExz5zCbz9zK; };
    struct { uint64_t zExt_DataAddr_OKzIz8ECapExz5zCbz9zK; };
  } variants;
};

// union Ext_ControlAddr_Check<(ECapEx%,b)>
enum kind_zExt_ControlAddr_CheckzIz8ECapExz5zCbz9zK { Kind_zExt_ControlAddr_ErrorzIz8ECapExz5zCbz9zK, Kind_zExt_ControlAddr_OKzIz8ECapExz5zCbz9zK };

struct zExt_ControlAddr_CheckzIz8ECapExz5zCbz9zK {
  enum kind_zExt_ControlAddr_CheckzIz8ECapExz5zCbz9zK kind;
  union {
    struct { struct ztuple_z8z5enumz0zzCapExzCz0z5bvz9 zExt_ControlAddr_ErrorzIz8ECapExz5zCbz9zK; };
    struct { uint64_t zExt_ControlAddr_OKzIz8ECapExz5zCbz9zK; };
  } variants;
};

// type abbreviation CapBits
typedef uint64_t zCapBits;

// type abbreviation CapAddrBits
typedef uint64_t zCapAddrBits;

// enum CPtrCmpOp
enum zCPtrCmpOp { zCEQ, zCNE, zCLT, zCLE, zCLTU, zCLEU, zCEXEQ, zCNEXEQ };

// enum Architecture
enum zArchitecture { zRV32, zRV64, zRV128 };

// union option<EArchitecture%>
enum kind_zoptionzIEArchitecturez5zK { Kind_zNonezIEArchitecturez5zK, Kind_zSomezIEArchitecturez5zK };

struct zoptionzIEArchitecturez5zK {
  enum kind_zoptionzIEArchitecturez5zK kind;
  union {
    struct { unit zNonezIEArchitecturez5zK; };
    struct { enum zArchitecture zSomezIEArchitecturez5zK; };
  } variants;
};

// struct tuple_(%enum zext_access_type, %enum zext_access_type)
struct ztuple_z8z5enumz0zzext_access_typezCz0z5enumz0zzext_access_typez9 {
  enum zext_access_type ztup0;
  enum zext_access_type ztup1;
};

// union AccessType<Eext_access_type%>
enum kind_zAccessTypezIEext_access_typez5zK { Kind_zExecutezIEext_access_typez5zK, Kind_zReadzIEext_access_typez5zK, Kind_zReadWritezIEext_access_typez5zK, Kind_zWritezIEext_access_typez5zK };

struct zAccessTypezIEext_access_typez5zK {
  enum kind_zAccessTypezIEext_access_typez5zK kind;
  union {
    struct { unit zExecutezIEext_access_typez5zK; };
    struct { enum zext_access_type zReadzIEext_access_typez5zK; };
    struct { struct ztuple_z8z5enumz0zzext_access_typezCz0z5enumz0zzext_access_typez9 zReadWritezIEext_access_typez5zK; };
    struct { enum zext_access_type zWritezIEext_access_typez5zK; };
  } variants;
};

struct zz5vecz8z5bv32z9 {
  size_t len;
  uint64_t *data;
};
typedef struct zz5vecz8z5bv32z9 zz5vecz8z5bv32z9;

struct zz5vecz8z5structz0zzPmpcfg_entz9 {
  size_t len;
  struct zPmpcfg_ent *data;
};
typedef struct zz5vecz8z5structz0zzPmpcfg_entz9 zz5vecz8z5structz0zzPmpcfg_entz9;

// struct tuple_(%i, %string)
struct ztuple_z8z5izCz0z5stringz9 {
  sail_int ztup0;
  sail_string ztup1;
};

// struct tuple_(%i64, %string)
struct ztuple_z8z5i64zCz0z5stringz9 {
  int64_t ztup0;
  sail_string ztup1;
};

// struct tuple_(%bv32, %bv33)
struct ztuple_z8z5bv32zCz0z5bv33z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%i64, %i64)
struct ztuple_z8z5i64zCz0z5i64z9 {
  int64_t ztup0;
  int64_t ztup1;
};

// struct tuple_(%bool, %struct zCapability)
struct ztuple_z8z5boolzCz0z5structz0zzCapabilityz9 {
  bool ztup0;
  struct zCapability ztup1;
};

// struct tuple_(%bool, %bool)
struct ztuple_z8z5boolzCz0z5boolz9 {
  bool ztup0;
  bool ztup1;
};

// struct tuple_(%bv32, %bv32)
struct ztuple_z8z5bv32zCz0z5bv32z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv12, %enum zPrivilege)
struct ztuple_z8z5bv12zCz0z5enumz0zzPrivilegez9 {
  uint64_t ztup0;
  enum zPrivilege ztup1;
};

// struct tuple_(%bv12, %bv32)
struct ztuple_z8z5bv12zCz0z5bv32z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv32, %enum zPrivilege)
struct ztuple_z8z5bv32zCz0z5enumz0zzPrivilegez9 {
  uint64_t ztup0;
  enum zPrivilege ztup1;
};

// struct tuple_(%enum zPrivilege, %union zctl_result)
struct ztuple_z8z5enumz0zzPrivilegezCz0z5unionz0zzctl_resultz9 {
  enum zPrivilege ztup0;
  struct zctl_result ztup1;
};

// struct tuple_(%bool, %bool, %bool)
struct ztuple_z8z5boolzCz0z5boolzCz0z5boolz9 {
  bool ztup0;
  bool ztup1;
  bool ztup2;
};

// struct tuple_(%union zAccessTypezIEext_access_typez5zK, %union zoptionzIz8bzCoz9zK)
struct ztuple_z8z5unionz0zzAccessTypezzIEext_access_typezz5zzKzCz0z5unionz0zzoptionzzIzz8bzzCozz9zzKz9 {
  struct zAccessTypezIEext_access_typez5zK ztup0;
  struct zoptionzIz8bzCoz9zK ztup1;
};

// struct tuple_(%union zAccessTypezIEext_access_typez5zK, %enum zPrivilege)
struct ztuple_z8z5unionz0zzAccessTypezzIEext_access_typezz5zzKzCz0z5enumz0zzPrivilegez9 {
  struct zAccessTypezIEext_access_typez5zK ztup0;
  enum zPrivilege ztup1;
};

// struct tuple_(%bool, %union zAccessTypezIEext_access_typez5zK)
struct ztuple_z8z5boolzCz0z5unionz0zzAccessTypezzIEext_access_typezz5zzKz9 {
  bool ztup0;
  struct zAccessTypezIEext_access_typez5zK ztup1;
};

// struct tuple_(%bool, %struct zext_ptw)
struct ztuple_z8z5boolzCz0z5structz0zzext_ptwz9 {
  bool ztup0;
  struct zext_ptw ztup1;
};

// struct tuple_(%struct zPTE_Bits, %bv10)
struct ztuple_z8z5structz0zzPTE_BitszCz0z5bv10z9 {
  struct zPTE_Bits ztup0;
  uint64_t ztup1;
};

// struct tuple_(%union zAccessTypezIEext_access_typez5zK, %union zPTW_Error)
struct ztuple_z8z5unionz0zzAccessTypezzIEext_access_typezz5zzKzCz0z5unionz0zzPTW_Errorz9 {
  struct zAccessTypezIEext_access_typez5zK ztup0;
  struct zPTW_Error ztup1;
};

// struct tuple_(%union zoptionzIbzK, %union zoptionzIbzK)
struct ztuple_z8z5unionz0zzoptionzzIbzzKzCz0z5unionz0zzoptionzzIbzzKz9 {
  struct zoptionzIbzK ztup0;
  struct zoptionzIbzK ztup1;
};

// struct tuple_(%bv34, %struct zSV32_PTE, %bv34, %i, %bool, %struct zext_ptw)
struct ztuple_z8z5bv34zCz0z5structz0zzSV32_PTEzCz0z5bv34zCz0z5izCz0z5boolzCz0z5structz0zzext_ptwz9 {
  uint64_t ztup0;
  struct zSV32_PTE ztup1;
  uint64_t ztup2;
  sail_int ztup3;
  bool ztup4;
  struct zext_ptw ztup5;
};

// struct tuple_(%i64, %struct zTLB_Entry)
struct ztuple_z8z5i64zCz0z5structz0zzTLB_Entryz9 {
  int64_t ztup0;
  struct zTLB_Entry ztup1;
};

// struct tuple_(%bv34, %struct zext_ptw)
struct ztuple_z8z5bv34zCz0z5structz0zzext_ptwz9 {
  uint64_t ztup0;
  struct zext_ptw ztup1;
};

// struct tuple_(%bv32, %struct zext_ptw)
struct ztuple_z8z5bv32zCz0z5structz0zzext_ptwz9 {
  uint64_t ztup0;
  struct zext_ptw ztup1;
};

// struct tuple_(%bv12, %i64)
struct ztuple_z8z5bv12zCz0z5i64z9 {
  uint64_t ztup0;
  int64_t ztup1;
};

// struct tuple_(%bool, %enum zcsrop)
struct ztuple_z8z5boolzCz0z5enumz0zzcsropz9 {
  bool ztup0;
  enum zcsrop ztup1;
};

// struct tuple_(%bool, %enum zword_width)
struct ztuple_z8z5boolzCz0z5enumz0zzword_widthz9 {
  bool ztup0;
  enum zword_width ztup1;
};

// struct tuple_(%union zoptionzIEArchitecturez5zK, %bv1)
struct ztuple_z8z5unionz0zzoptionzzIEArchitecturezz5zzKzCz0z5bv1z9 {
  struct zoptionzIEArchitecturez5zK ztup0;
  uint64_t ztup1;
};

// struct tuple_(%enum zRetired, %bool)
struct ztuple_z8z5enumz0zzRetiredzCz0z5boolz9 {
  enum zRetired ztup0;
  bool ztup1;
};

bool zneq_int(sail_int, sail_int);

bool zneq_bool(bool, bool);

void z__id(sail_int *rop, sail_int);

void zsail_ones(lbits *rop, sail_int);

bool zneq_anythingzIUAccessTypezIEext_access_typez5zKzK(struct zAccessTypezIEext_access_typez5zK, struct zAccessTypezIEext_access_typez5zK);

bool zneq_anythingzIEPrivilegez5zK(enum zPrivilege, enum zPrivilege);

void zhex_bits_forwards(struct ztuple_z8z5izCz0z5stringz9 *rop, lbits);

bool zhex_bits_forwards_matches(lbits);

void zhex_bits_4_forwards(sail_string *rop, uint64_t);

void zhex_bits_4_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_5_forwards(sail_string *rop, uint64_t);

void zhex_bits_5_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_6_forwards(sail_string *rop, uint64_t);

void zhex_bits_6_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_7_forwards(sail_string *rop, uint64_t);

void zhex_bits_7_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_8_forwards(sail_string *rop, uint64_t);

void zhex_bits_8_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_9_forwards(sail_string *rop, uint64_t);

void zhex_bits_9_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_10_forwards(sail_string *rop, uint64_t);

void zhex_bits_10_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_11_forwards(sail_string *rop, uint64_t);

void zhex_bits_11_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_12_forwards(sail_string *rop, uint64_t);

void zhex_bits_12_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_13_forwards(sail_string *rop, uint64_t);

void zhex_bits_13_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_16_forwards(sail_string *rop, uint64_t);

void zhex_bits_16_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_20_forwards(sail_string *rop, uint64_t);

void zhex_bits_20_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_21_forwards(sail_string *rop, uint64_t);

void zhex_bits_21_forwards_infallible(sail_string *rop, uint64_t);

void zhex_bits_32_forwards(sail_string *rop, uint64_t);

void zhex_bits_32_forwards_infallible(sail_string *rop, uint64_t);

bool znot(bool);

void zsign_extend(lbits *rop, sail_int, lbits);

void zzzero_extend(lbits *rop, sail_int, lbits);

void zzzeros_implicit(lbits *rop, sail_int);

void zones(lbits *rop, sail_int);

uint64_t zbool_to_bit(bool);

uint64_t zbool_to_bits(bool);

bool zbit_to_bool(uint64_t);

void zto_bits(lbits *rop, sail_int, sail_int);

bool zz8operatorz0zI_sz9(lbits, lbits);

bool zz8operatorz0zKzJ_sz9(lbits, lbits);

bool zz8operatorz0zI_uz9(lbits, lbits);

bool zz8operatorz0zKzJ_uz9(lbits, lbits);

bool zz8operatorz0zIzJ_uz9(lbits, lbits);

uint64_t zshift_right_arith32(uint64_t, uint64_t);

void zrotate_bits_right(lbits *rop, lbits, lbits);

void zrotate_bits_left(lbits *rop, lbits, lbits);

uint64_t zreverse_bits_in_byte(uint64_t);

int64_t zget_vlen_pow(unit);

void zMAX(sail_int *rop, sail_int);

void zalign_down(lbits *rop, sail_int, lbits);

void create_letbind_0(void);
void kill_letbind_0(void);


void create_letbind_1(void);
void kill_letbind_1(void);


void create_letbind_2(void);
void kill_letbind_2(void);


void create_letbind_3(void);
void kill_letbind_3(void);


void create_letbind_4(void);
void kill_letbind_4(void);


void create_letbind_5(void);
void kill_letbind_5(void);


uint64_t zCapExCode(enum zCapEx);

void zstring_of_capex(sail_string *rop, enum zCapEx);

void create_letbind_6(void);
void kill_letbind_6(void);


void create_letbind_7(void);
void kill_letbind_7(void);


void create_letbind_8(void);
void kill_letbind_8(void);


void create_letbind_9(void);
void kill_letbind_9(void);


void create_letbind_10(void);
void kill_letbind_10(void);


void create_letbind_11(void);
void kill_letbind_11(void);


void create_letbind_12(void);
void kill_letbind_12(void);


void create_letbind_13(void);
void kill_letbind_13(void);


void create_letbind_14(void);
void kill_letbind_14(void);


void create_letbind_15(void);
void kill_letbind_15(void);


void create_letbind_16(void);
void kill_letbind_16(void);


struct zEncCapability zcapBitsToEncCapability(uint64_t);

uint64_t zencCapToBits(struct zEncCapability);

void create_letbind_17(void);
void kill_letbind_17(void);


void create_letbind_18(void);
void kill_letbind_18(void);


void create_letbind_19(void);
void kill_letbind_19(void);


void create_letbind_20(void);
void kill_letbind_20(void);


void create_letbind_21(void);
void kill_letbind_21(void);


void create_letbind_22(void);
void kill_letbind_22(void);


struct zCapability zundefined_Capability(unit);

void create_letbind_23(void);
void kill_letbind_23(void);


void create_letbind_24(void);
void kill_letbind_24(void);


void create_letbind_25(void);
void kill_letbind_25(void);


void create_letbind_26(void);
void kill_letbind_26(void);


void create_letbind_27(void);
void kill_letbind_27(void);


struct zCapability zencCapabilityToCapability(bool, struct zEncCapability);

struct zCapability zcapBitsToCapability(bool, uint64_t);

struct zEncCapability zcapToEncCap(struct zCapability);

uint64_t zcapToBits(struct zCapability);

void create_letbind_28(void);
void kill_letbind_28(void);


struct ztuple_z8z5bv32zCz0z5bv33z9 zgetCapBoundsBits(struct zCapability);

struct ztuple_z8z5i64zCz0z5i64z9 zgetCapBounds(struct zCapability);

struct ztuple_z8z5boolzCz0z5structz0zzCapabilityz9 zsetCapBounds(struct zCapability, uint64_t, uint64_t);

struct zCapability zsetCapBoundsRoundDown(struct zCapability, uint64_t, uint64_t);

uint64_t zgetCapPerms(struct zCapability);

struct zCapability zsetCapPerms(struct zCapability, uint64_t);

bool zisCapSealed(struct zCapability);

bool zisCapForwardSentry(struct zCapability);

bool zisCapBackwardSentry(struct zCapability);

bool zisCapForwardInheritSentry(struct zCapability);

struct zCapability zsealCap(struct zCapability, uint64_t);

struct zCapability zunsealCap(struct zCapability);

uint64_t zgetCapBaseBits(struct zCapability);

uint64_t zgetCapTopBits(struct zCapability);

int64_t zgetCapTop(struct zCapability);

int64_t zgetCapLength(struct zCapability);

bool zinCapBounds(struct zCapability, uint64_t, int64_t);

struct zCapability zclearTagIf(struct zCapability, bool);

struct zCapability zclearTagIfSealed(struct zCapability);

struct zCapability zclearTag(struct zCapability);

bool zcapBoundsEqual(struct zCapability, struct zCapability);

struct ztuple_z8z5boolzCz0z5structz0zzCapabilityz9 zsetCapAddr(struct zCapability, uint64_t);

struct ztuple_z8z5boolzCz0z5structz0zzCapabilityz9 zincCapAddr(struct zCapability, uint64_t);

void zcapToString(sail_string *rop, struct zCapability);

uint64_t zgetRepresentableAlignmentMask(uint64_t);

uint64_t zgetRepresentableLength(uint64_t);

void create_letbind_29(void);
void kill_letbind_29(void);


uint64_t zaddr_to_tag_addr(uint64_t);

uint64_t ztag_addr_to_addr(uint64_t);

unit z__WriteRAM_Meta(uint64_t, sail_int, bool);

bool z__ReadRAM_Meta(uint64_t, sail_int);

bool zwrite_ram(enum zwrite_kind, uint64_t, int64_t, lbits, bool);

unit zwrite_ram_ea(enum zwrite_kind, uint64_t, int64_t);

void zread_ram(struct ztuple_z8z5bvzCz0z5boolz9 *rop, enum zread_kind, uint64_t, int64_t, bool);

struct zRVFI_DII_Instruction_Packet zundefined_RVFI_DII_Instruction_Packet(unit);

struct zRVFI_DII_Instruction_Packet zMk_RVFI_DII_Instruction_Packet(uint64_t);

uint64_t z_get_RVFI_DII_Instruction_Packet_rvfi_cmd(struct zRVFI_DII_Instruction_Packet);

uint64_t z_get_RVFI_DII_Instruction_Packet_rvfi_insn(struct zRVFI_DII_Instruction_Packet);

unit zrvfi_set_instr_packet(uint64_t);

uint64_t zrvfi_get_cmd(unit);

uint64_t zrvfi_get_insn(unit);

unit zprint_instr_packet(uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_halt(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_insn(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_intr(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_mem_addr(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_mem_rdata(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_mem_rmask(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_mem_wdata(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_mem_wmask(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_order(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_pc_rdata(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_pc_wdata(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rd_addr(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rd_wdata(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rs1_addr(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rs1_data(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rs2_addr(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_rs2_data(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void z_update_RVFI_DII_Execution_Packet_V1_rvfi_trap(struct zRVFI_DII_Execution_Packet_V1 *rop, struct zRVFI_DII_Execution_Packet_V1, uint64_t);

void zundefined_RVFI_DII_Execution_Packet_InstMetaData(struct zRVFI_DII_Execution_Packet_InstMetaData *rop, unit);

uint64_t z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_halt(struct zRVFI_DII_Execution_Packet_InstMetaData);

void z_update_RVFI_DII_Execution_Packet_InstMetaData_rvfi_halt(struct zRVFI_DII_Execution_Packet_InstMetaData *rop, struct zRVFI_DII_Execution_Packet_InstMetaData, uint64_t);

unit z_set_RVFI_DII_Execution_Packet_InstMetaData_rvfi_halt(struct zRVFI_DII_Execution_Packet_InstMetaData*, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_insn(struct zRVFI_DII_Execution_Packet_InstMetaData);

void z_update_RVFI_DII_Execution_Packet_InstMetaData_rvfi_insn(struct zRVFI_DII_Execution_Packet_InstMetaData *rop, struct zRVFI_DII_Execution_Packet_InstMetaData, uint64_t);

unit z_set_RVFI_DII_Execution_Packet_InstMetaData_rvfi_insn(struct zRVFI_DII_Execution_Packet_InstMetaData*, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_intr(struct zRVFI_DII_Execution_Packet_InstMetaData);

uint64_t z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_order(struct zRVFI_DII_Execution_Packet_InstMetaData);

uint64_t z_get_RVFI_DII_Execution_Packet_InstMetaData_rvfi_trap(struct zRVFI_DII_Execution_Packet_InstMetaData);

void zundefined_RVFI_DII_Execution_Packet_PC(struct zRVFI_DII_Execution_Packet_PC *rop, unit);

uint64_t z_get_RVFI_DII_Execution_Packet_PC_rvfi_pc_rdata(struct zRVFI_DII_Execution_Packet_PC);

uint64_t z_get_RVFI_DII_Execution_Packet_PC_rvfi_pc_wdata(struct zRVFI_DII_Execution_Packet_PC);

void z_update_RVFI_DII_Execution_Packet_PC_rvfi_pc_wdata(struct zRVFI_DII_Execution_Packet_PC *rop, struct zRVFI_DII_Execution_Packet_PC, uint64_t);

unit z_set_RVFI_DII_Execution_Packet_PC_rvfi_pc_wdata(struct zRVFI_DII_Execution_Packet_PC*, uint64_t);

void zundefined_RVFI_DII_Execution_Packet_Ext_Integer(struct zRVFI_DII_Execution_Packet_Ext_Integer *rop, unit);

void z_update_RVFI_DII_Execution_Packet_Ext_Integer_magic(struct zRVFI_DII_Execution_Packet_Ext_Integer *rop, struct zRVFI_DII_Execution_Packet_Ext_Integer, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_addr(struct zRVFI_DII_Execution_Packet_Ext_Integer);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rd_wdata(struct zRVFI_DII_Execution_Packet_Ext_Integer);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rs1_addr(struct zRVFI_DII_Execution_Packet_Ext_Integer);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rs1_rdata(struct zRVFI_DII_Execution_Packet_Ext_Integer);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rs2_addr(struct zRVFI_DII_Execution_Packet_Ext_Integer);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_Integer_rvfi_rs2_rdata(struct zRVFI_DII_Execution_Packet_Ext_Integer);

void zundefined_RVFI_DII_Execution_Packet_Ext_MemAccess(struct zRVFI_DII_Execution_Packet_Ext_MemAccess *rop, unit);

void z_update_RVFI_DII_Execution_Packet_Ext_MemAccess_magic(struct zRVFI_DII_Execution_Packet_Ext_MemAccess *rop, struct zRVFI_DII_Execution_Packet_Ext_MemAccess, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_addr(struct zRVFI_DII_Execution_Packet_Ext_MemAccess);

void z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_MemAccess);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_rmask(struct zRVFI_DII_Execution_Packet_Ext_MemAccess);

void z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_MemAccess);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_MemAccess_rvfi_mem_wmask(struct zRVFI_DII_Execution_Packet_Ext_MemAccess);

void zundefined_RVFI_DII_Execution_Packet_Ext_CSR(struct zRVFI_DII_Execution_Packet_Ext_CSR *rop, unit);

void z_update_RVFI_DII_Execution_Packet_Ext_CSR_magic(struct zRVFI_DII_Execution_Packet_Ext_CSR *rop, struct zRVFI_DII_Execution_Packet_Ext_CSR, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CSR_rvfi_csr_addr(struct zRVFI_DII_Execution_Packet_Ext_CSR);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CSR_rvfi_csr_rdata(struct zRVFI_DII_Execution_Packet_Ext_CSR);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CSR_rvfi_csr_wdata(struct zRVFI_DII_Execution_Packet_Ext_CSR);

void zundefined_RVFI_DII_Execution_Packet_Ext_CHERI(struct zRVFI_DII_Execution_Packet_Ext_CHERI *rop, unit);

void z_update_RVFI_DII_Execution_Packet_Ext_CHERI_magic(struct zRVFI_DII_Execution_Packet_Ext_CHERI *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_addr(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

void z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_wdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cd_wtag(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs1_addr(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

void z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs1_rdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs1_rtag(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs2_addr(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

void z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs2_rdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_rvfi_cs2_rtag(struct zRVFI_DII_Execution_Packet_Ext_CHERI);

void zundefined_RVFI_DII_Execution_Packet_Ext_CHERI_SCR(struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR *rop, unit);

void z_update_RVFI_DII_Execution_Packet_Ext_CHERI_SCR_magic(struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR, uint64_t);

uint64_t z_get_RVFI_DII_Execution_Packet_Ext_CHERI_SCR_rvfi_scr_addr(struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR);

void z_get_RVFI_DII_Execution_Packet_Ext_CHERI_SCR_rvfi_scr_rdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR);

void z_get_RVFI_DII_Execution_Packet_Ext_CHERI_SCR_rvfi_scr_wdata(lbits *rop, struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR);

void z_update_RVFI_DII_Execution_PacketV2_basic_data(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, lbits);

void z_update_RVFI_DII_Execution_PacketV2_cheri_data_available(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

void z_update_RVFI_DII_Execution_PacketV2_cheri_scr_read_write_data_available(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

void z_update_RVFI_DII_Execution_PacketV2_csr_read_write_data_available(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

void z_update_RVFI_DII_Execution_PacketV2_integer_data_available(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

void z_update_RVFI_DII_Execution_PacketV2_memory_access_data_available(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

void z_update_RVFI_DII_Execution_PacketV2_pc_data(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, lbits);

void z_update_RVFI_DII_Execution_PacketV2_trace_sizze(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, uint64_t);

unit zrvfi_zzero_exec_packet(unit);

unit zrvfi_halt_exec_packet(unit);

void zrvfi_get_v2_support_packet(lbits *rop, unit);

void zrvfi_get_exec_packet_v1(lbits *rop, unit);

uint64_t zrvfi_get_v2_trace_sizze(unit);

void zrvfi_get_exec_packet_v2(lbits *rop, unit);

void zrvfi_get_int_data(lbits *rop, unit);

void zrvfi_get_mem_data(lbits *rop, unit);

void zrvfi_get_csr_data(lbits *rop, unit);

void zrvfi_get_cheri_data(lbits *rop, unit);

void zrvfi_get_cheri_scr_data(lbits *rop, unit);

uint64_t zrvfi_encode_width_mask(int64_t);

unit zprint_rvfi_exec(unit);

struct zext_ptw zext_ptw_lc_join(struct zext_ptw, enum zext_ptw_lc);

struct zext_ptw zext_ptw_sc_join(struct zext_ptw, enum zext_ptw_sc);

void create_letbind_30(void);
void kill_letbind_30(void);


uint64_t zext_exc_type_to_bits(enum zext_exc_type);

int64_t znum_of_ext_exc_type(enum zext_exc_type);

void zext_exc_type_to_str(sail_string *rop, enum zext_exc_type);

void create_letbind_31(void);
void kill_letbind_31(void);


void create_letbind_32(void);
void kill_letbind_32(void);


void create_letbind_33(void);
void kill_letbind_33(void);


void create_letbind_34(void);
void kill_letbind_34(void);


uint64_t zcreg2reg_idx(uint64_t);

void create_letbind_35(void);
void kill_letbind_35(void);


void create_letbind_36(void);
void kill_letbind_36(void);


void create_letbind_37(void);
void kill_letbind_37(void);


void zarchitecture(struct zoptionzIEArchitecturez5zK *rop, uint64_t);

void znot_implementedzIUExt_FetchAddr_CheckzIECapExz5zKzK(struct zExt_FetchAddr_CheckzIECapExz5zK *rop, const_sail_string);

uint64_t zinternal_errorzIB32zK(const_sail_string, sail_int, const_sail_string);

uint64_t zinternal_errorzIB1zK(const_sail_string, sail_int, const_sail_string);

unit zinternal_errorzIuzK(const_sail_string, sail_int, const_sail_string);

bool zinternal_errorzIozK(const_sail_string, sail_int, const_sail_string);

struct ztuple_z8z5boolzCz0z5boolz9 zinternal_errorzIz8ozCoz9zK(const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUTR_ResultzIbzCUExceptionTypezKzK(struct zTR_ResultzIbzCUExceptionTypezK *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUExt_FetchAddr_CheckzIECapExz5zKzK(struct zExt_FetchAddr_CheckzIECapExz5zK *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUExceptionTypezK(struct zExceptionType *rop, const_sail_string, sail_int, const_sail_string);

enum zSATPMode zinternal_errorzIESATPModez5zK(const_sail_string, sail_int, const_sail_string);

enum zRetired zinternal_errorzIERetiredz5zK(const_sail_string, sail_int, const_sail_string);

enum zPrivilege zinternal_errorzIEPrivilegez5zK(const_sail_string, sail_int, const_sail_string);

enum zArchitecture zinternal_errorzIEArchitecturez5zK(const_sail_string, sail_int, const_sail_string);

enum zPrivilege zundefined_Privilege(unit);

uint64_t zprivLevel_to_bits(enum zPrivilege);

enum zPrivilege zprivLevel_of_bits(uint64_t);

void zprivLevel_to_str(sail_string *rop, enum zPrivilege);

uint64_t zinterruptType_to_bits(enum zInterruptType);

uint64_t zexceptionType_to_bits(struct zExceptionType);

int64_t znum_of_ExceptionType(struct zExceptionType);

void zexceptionType_to_str(sail_string *rop, struct zExceptionType);

enum zTrapVectorMode ztrapVectorMode_of_bits(uint64_t);

enum zExtStatus zextStatus_of_bits(uint64_t);

bool zbool_bits_backwards(uint64_t);

bool zbool_bits_backwards_matches(uint64_t);

bool zbool_bits_backwards_infallible(uint64_t);

bool zbool_not_bits_backwards(uint64_t);

bool zbool_not_bits_backwards_matches(uint64_t);

bool zbool_not_bits_backwards_infallible(uint64_t);

enum zword_width zsizze_bits_backwards(uint64_t);

bool zsizze_bits_backwards_matches(uint64_t);

enum zword_width zsizze_bits_backwards_infallible(uint64_t);

void zsizze_mnemonic_forwards(sail_string *rop, enum zword_width);

void zsizze_mnemonic_forwards_infallible(sail_string *rop, enum zword_width);

int64_t zword_width_bytes(enum zword_width);

void zreport_invalid_widthzIUMemoryOpResultzIozKzK(struct zMemoryOpResultzIozK *rop, const_sail_string, sail_int, enum zword_width, const_sail_string);

enum zRetired zreport_invalid_widthzIERetiredz5zK(const_sail_string, sail_int, enum zword_width, const_sail_string);

void create_letbind_38(void);
void kill_letbind_38(void);


void create_letbind_39(void);
void kill_letbind_39(void);


void zRegStr(sail_string *rop, struct zCapability);

uint64_t zregval_from_reg(struct zCapability);

struct zCapability zregval_into_reg(uint64_t);

void zcsr_name_map_forwards(sail_string *rop, uint64_t);

void zcsr_name(sail_string *rop, uint64_t);

bool zext_is_CSR_defined(uint64_t, enum zPrivilege);

void zext_read_CSR(struct zoptionzIbzK *rop, uint64_t);

void zext_write_CSR(struct zoptionzIbzK *rop, uint64_t, uint64_t);

void zscr_name_map_forwards(sail_string *rop, uint64_t);

void zscr_name_map_forwards_infallible(sail_string *rop, uint64_t);

void create_letbind_40(void);
void kill_letbind_40(void);


void zaccessType_to_str(sail_string *rop, struct zAccessTypezIEext_access_typez5zK);

unit zrvfi_rX(int64_t, enum zregor, uint64_t);

uint64_t zrX(int64_t, enum zregor);

unit zrvfi_wX(int64_t, uint64_t);

unit zwX(int64_t, uint64_t);

uint64_t zrX_bits(uint64_t, enum zregor);

unit zwX_bits(uint64_t, uint64_t);

void zreg_name_abi(sail_string *rop, uint64_t);

void zreg_name_forwards(sail_string *rop, uint64_t);

void zreg_name_forwards_infallible(sail_string *rop, uint64_t);

void zcreg_name_forwards(sail_string *rop, uint64_t);

void zcreg_name_forwards_infallible(sail_string *rop, uint64_t);

unit zinit_base_regs(unit);

struct zMisa zundefined_Misa(unit);

struct zMisa zMk_Misa(uint64_t);

struct zMisa z_update_Misa_B(struct zMisa, uint64_t);

unit z_set_Misa_B(struct zMisa*, uint64_t);

uint64_t z_get_Misa_C(struct zMisa);

struct zMisa z_update_Misa_C(struct zMisa, uint64_t);

unit z_set_Misa_C(struct zMisa*, uint64_t);

uint64_t z_get_Misa_D(struct zMisa);

struct zMisa z_update_Misa_D(struct zMisa, uint64_t);

uint64_t z_get_Misa_F(struct zMisa);

struct zMisa z_update_Misa_F(struct zMisa, uint64_t);

uint64_t z_get_Misa_M(struct zMisa);

uint64_t z_get_Misa_MXL(struct zMisa);

uint64_t z_get_Misa_N(struct zMisa);

uint64_t z_get_Misa_S(struct zMisa);

uint64_t z_get_Misa_U(struct zMisa);

uint64_t z_get_Misa_X(struct zMisa);

struct zMisa z_update_Misa_X(struct zMisa, uint64_t);

unit z_set_Misa_X(struct zMisa*, uint64_t);

bool zext_veto_disable_C(unit);

struct zMisa zlegalizze_misa(struct zMisa, uint64_t);

bool zhaveRVC(unit);

bool zhaveMulDiv(unit);

bool zhaveSupMode(unit);

bool zhaveUsrMode(unit);

bool zhaveNExt(unit);

struct zMstatush zundefined_Mstatush(unit);

struct zMstatus zundefined_Mstatus(unit);

struct zMstatus zMk_Mstatus(uint64_t);

uint64_t z_get_Mstatus_FS(struct zMstatus);

struct zMstatus z_update_Mstatus_FS(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_MIE(struct zMstatus);

struct zMstatus z_update_Mstatus_MIE(struct zMstatus, uint64_t);

unit z_set_Mstatus_MIE(struct zMstatus*, uint64_t);

uint64_t z_get_Mstatus_MPIE(struct zMstatus);

uint64_t z_get_Mstatus_MPP(struct zMstatus);

uint64_t z_get_Mstatus_MPRV(struct zMstatus);

struct zMstatus z_update_Mstatus_MPRV(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_MXR(struct zMstatus);

struct zMstatus z_update_Mstatus_MXR(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_SD(struct zMstatus);

struct zMstatus z_update_Mstatus_SD(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_SIE(struct zMstatus);

struct zMstatus z_update_Mstatus_SIE(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_SPIE(struct zMstatus);

struct zMstatus z_update_Mstatus_SPIE(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_SPP(struct zMstatus);

struct zMstatus z_update_Mstatus_SPP(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_SUM(struct zMstatus);

struct zMstatus z_update_Mstatus_SUM(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_TSR(struct zMstatus);

uint64_t z_get_Mstatus_TVM(struct zMstatus);

uint64_t z_get_Mstatus_TW(struct zMstatus);

uint64_t z_get_Mstatus_UIE(struct zMstatus);

struct zMstatus z_update_Mstatus_UIE(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_UPIE(struct zMstatus);

struct zMstatus z_update_Mstatus_UPIE(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_VS(struct zMstatus);

struct zMstatus z_update_Mstatus_VS(struct zMstatus, uint64_t);

uint64_t z_get_Mstatus_XS(struct zMstatus);

struct zMstatus z_update_Mstatus_XS(struct zMstatus, uint64_t);

enum zPrivilege zeffectivePrivilege(struct zAccessTypezIEext_access_typez5zK, struct zMstatus, enum zPrivilege);

uint64_t zget_mstatus_SXL(struct zMstatus);

struct zMstatus zset_mstatus_SXL(struct zMstatus, uint64_t);

uint64_t zget_mstatus_UXL(struct zMstatus);

struct zMstatus zset_mstatus_UXL(struct zMstatus, uint64_t);

struct zMstatus zlegalizze_mstatus(struct zMstatus, uint64_t);

enum zArchitecture zcur_Architecture(unit);

struct zMinterrupts zundefined_Minterrupts(unit);

struct zMinterrupts zMk_Minterrupts(uint64_t);

uint64_t z_get_Minterrupts_MEI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_MEI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_MSI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_MSI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_MTI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_MTI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_SEI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_SEI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_SSI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_SSI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_STI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_STI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_UEI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_UEI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_USI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_USI(struct zMinterrupts, uint64_t);

uint64_t z_get_Minterrupts_UTI(struct zMinterrupts);

struct zMinterrupts z_update_Minterrupts_UTI(struct zMinterrupts, uint64_t);

struct zMinterrupts zlegalizze_mip(struct zMinterrupts, uint64_t);

struct zMinterrupts zlegalizze_mie(struct zMinterrupts, uint64_t);

struct zMinterrupts zlegalizze_mideleg(struct zMinterrupts, uint64_t);

struct zMedeleg zundefined_Medeleg(unit);

struct zMedeleg zMk_Medeleg(uint64_t);

struct zMedeleg z_update_Medeleg_MEnvCall(struct zMedeleg, uint64_t);

struct zMedeleg zlegalizze_medeleg(struct zMedeleg, uint64_t);

struct zMtvec zundefined_Mtvec(unit);

struct zMtvec zMk_Mtvec(uint64_t);

uint64_t z_get_Mtvec_Mode(struct zMtvec);

struct zMcause zundefined_Mcause(unit);

uint64_t zpc_alignment_mask(unit);

struct zCounteren zundefined_Counteren(unit);

uint64_t z_get_Counteren_CY(struct zCounteren);

struct zCounteren z_update_Counteren_CY(struct zCounteren, uint64_t);

uint64_t z_get_Counteren_IR(struct zCounteren);

struct zCounteren z_update_Counteren_IR(struct zCounteren, uint64_t);

uint64_t z_get_Counteren_TM(struct zCounteren);

struct zCounteren z_update_Counteren_TM(struct zCounteren, uint64_t);

struct zCounteren zlegalizze_mcounteren(struct zCounteren, uint64_t);

struct zCounteren zlegalizze_scounteren(struct zCounteren, uint64_t);

struct zCounterin zundefined_Counterin(unit);

uint64_t z_get_Counterin_CY(struct zCounterin);

struct zCounterin z_update_Counterin_CY(struct zCounterin, uint64_t);

uint64_t z_get_Counterin_IR(struct zCounterin);

struct zCounterin z_update_Counterin_IR(struct zCounterin, uint64_t);

struct zCounterin zlegalizze_mcountinhibit(struct zCounterin, uint64_t);

unit zretire_instruction(unit);

struct zSstatus zMk_Sstatus(uint64_t);

uint64_t z_get_Sstatus_FS(struct zSstatus);

struct zSstatus z_update_Sstatus_FS(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_MXR(struct zSstatus);

struct zSstatus z_update_Sstatus_MXR(struct zSstatus, uint64_t);

struct zSstatus z_update_Sstatus_SD(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_SIE(struct zSstatus);

struct zSstatus z_update_Sstatus_SIE(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_SPIE(struct zSstatus);

struct zSstatus z_update_Sstatus_SPIE(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_SPP(struct zSstatus);

struct zSstatus z_update_Sstatus_SPP(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_SUM(struct zSstatus);

struct zSstatus z_update_Sstatus_SUM(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_UIE(struct zSstatus);

struct zSstatus z_update_Sstatus_UIE(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_UPIE(struct zSstatus);

struct zSstatus z_update_Sstatus_UPIE(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_VS(struct zSstatus);

struct zSstatus z_update_Sstatus_VS(struct zSstatus, uint64_t);

uint64_t z_get_Sstatus_XS(struct zSstatus);

struct zSstatus z_update_Sstatus_XS(struct zSstatus, uint64_t);

struct zSstatus zset_sstatus_UXL(struct zSstatus, uint64_t);

struct zSstatus zlower_mstatus(struct zMstatus);

struct zMstatus zlift_sstatus(struct zMstatus, struct zSstatus);

struct zMstatus zlegalizze_sstatus(struct zMstatus, uint64_t);

struct zSedeleg zundefined_Sedeleg(unit);

struct zSedeleg zMk_Sedeleg(uint64_t);

struct zSedeleg zlegalizze_sedeleg(struct zSedeleg, uint64_t);

struct zSinterrupts zundefined_Sinterrupts(unit);

struct zSinterrupts zMk_Sinterrupts(uint64_t);

uint64_t z_get_Sinterrupts_SEI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_SEI(struct zSinterrupts, uint64_t);

uint64_t z_get_Sinterrupts_SSI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_SSI(struct zSinterrupts, uint64_t);

uint64_t z_get_Sinterrupts_STI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_STI(struct zSinterrupts, uint64_t);

uint64_t z_get_Sinterrupts_UEI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_UEI(struct zSinterrupts, uint64_t);

uint64_t z_get_Sinterrupts_USI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_USI(struct zSinterrupts, uint64_t);

uint64_t z_get_Sinterrupts_UTI(struct zSinterrupts);

struct zSinterrupts z_update_Sinterrupts_UTI(struct zSinterrupts, uint64_t);

struct zSinterrupts zlower_mip(struct zMinterrupts, struct zMinterrupts);

struct zSinterrupts zlower_mie(struct zMinterrupts, struct zMinterrupts);

struct zMinterrupts zlift_sip(struct zMinterrupts, struct zMinterrupts, struct zSinterrupts);

struct zMinterrupts zlegalizze_sip(struct zMinterrupts, struct zMinterrupts, uint64_t);

struct zMinterrupts zlift_sie(struct zMinterrupts, struct zMinterrupts, struct zSinterrupts);

struct zMinterrupts zlegalizze_sie(struct zMinterrupts, struct zMinterrupts, uint64_t);

struct zSatp32 zMk_Satp32(uint64_t);

uint64_t z_get_Satp32_Asid(struct zSatp32);

uint64_t z_get_Satp32_Mode(struct zSatp32);

uint64_t z_get_Satp32_PPN(struct zSatp32);

uint64_t zlegalizze_satp32(enum zArchitecture, uint64_t, uint64_t);

uint64_t zread_seed_csr(unit);

void zwrite_seed_csr(struct zoptionzIbzK *rop, unit);

struct zEnvcfg zundefined_Envcfg(unit);

struct zEnvcfg zMk_Envcfg(uint64_t);

uint64_t z_get_Envcfg_FIOM(struct zEnvcfg);

struct zEnvcfg z_update_Envcfg_FIOM(struct zEnvcfg, uint64_t);

struct zEnvcfg zlegalizze_envcfg(struct zEnvcfg, uint64_t);

bool zis_fiom_active(unit);

struct zVtype zundefined_Vtype(unit);

enum zPmpAddrMatchType zpmpAddrMatchType_of_bits(uint64_t);

struct zPmpcfg_ent zundefined_Pmpcfg_ent(unit);

struct zPmpcfg_ent zMk_Pmpcfg_ent(uint64_t);

uint64_t z_get_Pmpcfg_ent_A(struct zPmpcfg_ent);

struct zPmpcfg_ent z_update_Pmpcfg_ent_A(struct zPmpcfg_ent, uint64_t);

uint64_t z_get_Pmpcfg_ent_L(struct zPmpcfg_ent);

struct zPmpcfg_ent z_update_Pmpcfg_ent_L(struct zPmpcfg_ent, uint64_t);

uint64_t z_get_Pmpcfg_ent_R(struct zPmpcfg_ent);

struct zPmpcfg_ent z_update_Pmpcfg_ent_R(struct zPmpcfg_ent, uint64_t);

uint64_t z_get_Pmpcfg_ent_W(struct zPmpcfg_ent);

struct zPmpcfg_ent z_update_Pmpcfg_ent_W(struct zPmpcfg_ent, uint64_t);

uint64_t z_get_Pmpcfg_ent_X(struct zPmpcfg_ent);

struct zPmpcfg_ent z_update_Pmpcfg_ent_X(struct zPmpcfg_ent, uint64_t);

uint64_t zpmpReadCfgReg(int64_t);

uint64_t zpmpReadAddrReg(int64_t);

bool zpmpLocked(struct zPmpcfg_ent);

bool zpmpTORLocked(struct zPmpcfg_ent);

struct zPmpcfg_ent zpmpWriteCfg(int64_t, struct zPmpcfg_ent, uint64_t);

unit zpmpWriteCfgReg(int64_t, uint64_t);

uint64_t zpmpWriteAddr(bool, bool, uint64_t, uint64_t);

unit zpmpWriteAddrReg(int64_t, uint64_t);

void zpmpAddrRange(struct zoptionzIz8bzCbz9zK *rop, struct zPmpcfg_ent, uint64_t, uint64_t);

bool zpmpCheckRWX(struct zPmpcfg_ent, struct zAccessTypezIEext_access_typez5zK);

bool zpmpCheckPerms(struct zPmpcfg_ent, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege);

enum zpmpAddrMatch zpmpMatchAddr(uint64_t, uint64_t, struct zoptionzIz8bzCbz9zK);

enum zpmpMatch zpmpMatchEntry(uint64_t, uint64_t, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, struct zPmpcfg_ent, uint64_t, uint64_t);

void zaccessToFault(struct zExceptionType *rop, struct zAccessTypezIEext_access_typez5zK);

void zpmpCheck(struct zoptionzIUExceptionTypezK *rop, uint64_t, sail_int, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege);

unit zinit_pmp(unit);

struct zccsr zundefined_ccsr(unit);

struct zccsr zMk_ccsr(uint64_t);

uint64_t z_get_ccsr_bits(struct zccsr);

struct zccsr z_update_ccsr_d(struct zccsr, uint64_t);

unit z_set_ccsr_d(struct zccsr*, uint64_t);

struct zccsr z_update_ccsr_e(struct zccsr, uint64_t);

unit z_set_ccsr_e(struct zccsr*, uint64_t);

struct zccsr zlegalizze_ccsr(struct zccsr, uint64_t);

uint64_t zlegalizze_mshwm(uint64_t);

bool zhaveXcheri(unit);

unit zrvfi_rC(int64_t, enum zregor, uint64_t, bool);

struct zCapability zrC(int64_t, enum zregor);

unit zrvfi_wC(int64_t, uint64_t, bool);

unit zwC(int64_t, struct zCapability);

struct zCapability zrC_bits(uint64_t, enum zregor);

unit zwC_bits(uint64_t, struct zCapability);

unit zext_init_regs(unit);

unit zext_rvfi_init(unit);

void zcap_reg_name_abi(sail_string *rop, uint64_t);

void zcap_reg_name_forwards(sail_string *rop, uint64_t);

void zcap_reg_name_forwards_infallible(sail_string *rop, uint64_t);

void zcap_creg_name_forwards(sail_string *rop, uint64_t);

void zcap_creg_name_forwards_infallible(sail_string *rop, uint64_t);

void zstring_of_capreg_idx(sail_string *rop, uint64_t);

unit zset_next_pc(uint64_t);

unit ztick_pc(unit);

struct zVcsr zundefined_Vcsr(unit);

struct zUstatus zMk_Ustatus(uint64_t);

uint64_t z_get_Ustatus_UIE(struct zUstatus);

struct zUstatus z_update_Ustatus_UIE(struct zUstatus, uint64_t);

uint64_t z_get_Ustatus_UPIE(struct zUstatus);

struct zUstatus z_update_Ustatus_UPIE(struct zUstatus, uint64_t);

struct zUstatus zlower_sstatus(struct zSstatus);

struct zSstatus zlift_ustatus(struct zSstatus, struct zUstatus);

struct zMstatus zlegalizze_ustatus(struct zMstatus, uint64_t);

struct zUinterrupts zMk_Uinterrupts(uint64_t);

uint64_t z_get_Uinterrupts_UEI(struct zUinterrupts);

struct zUinterrupts z_update_Uinterrupts_UEI(struct zUinterrupts, uint64_t);

uint64_t z_get_Uinterrupts_USI(struct zUinterrupts);

struct zUinterrupts z_update_Uinterrupts_USI(struct zUinterrupts, uint64_t);

uint64_t z_get_Uinterrupts_UTI(struct zUinterrupts);

struct zUinterrupts z_update_Uinterrupts_UTI(struct zUinterrupts, uint64_t);

struct zUinterrupts zlower_sip(struct zSinterrupts, struct zSinterrupts);

struct zUinterrupts zlower_sie(struct zSinterrupts, struct zSinterrupts);

struct zSinterrupts zlift_uip(struct zSinterrupts, struct zSinterrupts, struct zUinterrupts);

struct zSinterrupts zlegalizze_uip(struct zSinterrupts, struct zSinterrupts, uint64_t);

struct zSinterrupts zlift_uie(struct zSinterrupts, struct zSinterrupts, struct zUinterrupts);

struct zSinterrupts zlegalizze_uie(struct zSinterrupts, struct zSinterrupts, uint64_t);

unit zhandle_trap_extension(enum zPrivilege, uint64_t, struct zoptionzIuzK);

uint64_t zprepare_trap_vector(enum zPrivilege, struct zMcause);

uint64_t zget_xret_target(enum zPrivilege);

uint64_t zset_xret_target(enum zPrivilege, uint64_t);

uint64_t zprepare_xret_target(enum zPrivilege);

uint64_t zget_mtvec(unit);

uint64_t zset_mtvec(uint64_t);

uint64_t zset_stvec(uint64_t);

uint64_t zset_utvec(uint64_t);

void zcsr_name_map_forwards_infallible(sail_string *rop, uint64_t);

uint64_t zcsrAccess(uint64_t);

uint64_t zcsrPriv(uint64_t);

bool zis_CSR_defined(uint64_t, enum zPrivilege);

bool zcheck_CSR_access(uint64_t, uint64_t, enum zPrivilege, bool);

bool zcheck_TVM_SATP(uint64_t, enum zPrivilege);

bool zcheck_Counteren(uint64_t, enum zPrivilege);

bool zcheck_seed_CSR(uint64_t, enum zPrivilege, bool);

bool zcheck_CSR(uint64_t, enum zPrivilege, bool);

enum zPrivilege zexception_delegatee(struct zExceptionType, enum zPrivilege);

void zfindPendingInterrupt(struct zoptionzIEInterruptTypez5zK *rop, uint64_t);

void zprocessPending(struct zinterrupt_set *rop, struct zMinterrupts, struct zMinterrupts, uint64_t, bool);

void zgetPendingSet(struct zoptionzIz8bzCEPrivilegez5z9zK *rop, enum zPrivilege);

void zdispatchInterrupt(struct zoptionzIz8EInterruptTypez5zCEPrivilegez5z9zK *rop, enum zPrivilege);

uint64_t ztval(struct zoptionzIbzK);

unit zrvfi_trap(unit);

uint64_t ztrap_handler(enum zPrivilege, bool, uint64_t, uint64_t, struct zoptionzIbzK, struct zoptionzIuzK);

uint64_t zexception_handler(enum zPrivilege, struct zctl_result, uint64_t);

unit zhandle_mem_exception(uint64_t, struct zExceptionType);

unit zhandle_interrupt(enum zInterruptType, enum zPrivilege);

unit zinit_sys(unit);

void zMemoryOpResult_add_metazIbzK(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zMemoryOpResultzIbzK, bool);

void zMemoryOpResult_drop_metazIbzK(struct zMemoryOpResultzIbzK *rop, struct zMemoryOpResultzIz8bzCoz9zK);

void zext_check_phys_mem_read(struct zExt_PhysAddr_Check *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t, bool, bool, bool, bool);

void zext_check_phys_mem_write(struct zExt_PhysAddr_Check *rop, enum zwrite_kind, uint64_t, int64_t, lbits, bool);

unit zhandle_cheri_cap_exception(enum zCapEx, uint64_t);

unit zhandle_cheri_reg_exception(enum zCapEx, uint64_t);

unit zhandle_cheri_pcc_exception(enum zCapEx);

bool zpcc_access_system_regs(unit);

void zext_fetch_check_pc(struct zExt_FetchAddr_CheckzIECapExz5zK *rop, uint64_t, uint64_t);

unit zext_handle_fetch_check_error(enum zCapEx);

void zext_control_check_addr(struct zExt_ControlAddr_CheckzIz8ECapExz5zCbz9zK *rop, uint64_t);

void zext_control_check_pc(struct zExt_ControlAddr_CheckzIz8ECapExz5zCbz9zK *rop, uint64_t);

unit zext_handle_control_check_error(struct ztuple_z8z5enumz0zzCapExzCz0z5bv6z9);

void zext_data_get_addr(struct zExt_DataAddr_CheckzIz8ECapExz5zCbz9zK *rop, uint64_t, uint64_t, struct zAccessTypezIEext_access_typez5zK, enum zword_width);

unit zext_handle_data_check_error(struct ztuple_z8z5enumz0zzCapExzCz0z5bv6z9);

bool zext_check_xret_priv(enum zPrivilege);

unit zext_fail_xret_priv(unit);

bool zext_check_CSR(uint64_t, enum zPrivilege, bool);

unit zext_check_CSR_fail(unit);

bool zwithin_phys_mem(uint64_t, sail_int);

bool zwithin_clint(uint64_t, int64_t);

bool zwithin_htif_writable(uint64_t, int64_t);

bool zwithin_htif_readable(uint64_t, int64_t);

bool zwithin_uart(uint64_t, int64_t);

void create_letbind_41(void);
void kill_letbind_41(void);


void create_letbind_42(void);
void kill_letbind_42(void);


void create_letbind_43(void);
void kill_letbind_43(void);


void create_letbind_44(void);
void kill_letbind_44(void);


void create_letbind_45(void);
void kill_letbind_45(void);


void zclint_load(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, sail_int);

unit zclint_dispatch(unit);

void zclint_store(struct zMemoryOpResultzIozK *rop, uint64_t, sail_int, lbits);

unit ztick_clock(unit);

struct zhtif_cmd zMk_htif_cmd(uint64_t);

uint64_t z_get_htif_cmd_cmd(struct zhtif_cmd);

uint64_t z_get_htif_cmd_device(struct zhtif_cmd);

uint64_t z_get_htif_cmd_payload(struct zhtif_cmd);

unit zreset_htif(unit);

void zhtif_load(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, sail_int);

void zhtif_store(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, sbits);

unit zhtif_tick(unit);

bool zwithin_mmio_readable(uint64_t, int64_t);

bool zwithin_mmio_writable(uint64_t, int64_t);

void create_letbind_46(void);
void kill_letbind_46(void);


void create_letbind_47(void);
void kill_letbind_47(void);


void create_letbind_48(void);
void kill_letbind_48(void);


void zuart_load(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, sail_int);

void zuart_store(struct zMemoryOpResultzIozK *rop, uint64_t, sail_int, lbits);

void zmmio_read(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t);

void zmmio_write(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits);

unit zinit_platform(unit);

unit ztick_platform(unit);

unit zhandle_illegal(unit);

unit zplatform_wfi(unit);

bool zis_aligned_addr(uint64_t, sail_int);

void zread_kind_of_flags(struct zoptionzIEread_kindz5zK *rop, bool, bool, bool);

void zphys_mem_read(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t, bool, bool, bool, bool);

void zchecked_mem_read(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t, bool, bool, bool, bool);

void zpmp_mem_read(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool, bool);

unit zrvfi_read(uint64_t, sail_int, struct zMemoryOpResultzIz8bzCoz9zK);

void zmem_read(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t, bool, bool, bool);

void zmem_read_priv(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool);

void zmem_read_meta(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zAccessTypezIEext_access_typez5zK, uint64_t, int64_t, bool, bool, bool, bool);

void zmem_read_priv_meta(struct zMemoryOpResultzIz8bzCoz9zK *rop, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool, bool);

void zmem_write_ea(struct zMemoryOpResultzIuzK *rop, uint64_t, int64_t, bool, bool, bool);

unit zrvfi_write(uint64_t, int64_t, lbits, bool, struct zMemoryOpResultzIozK);

void zphys_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, bool);

void zchecked_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, bool);

void zpmp_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, bool);

void zmem_write_value_priv_meta(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, bool, bool, bool, bool);

void zmem_write_value_priv(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, enum zPrivilege, bool, bool, bool);

void zmem_write_value_meta(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, enum zext_access_type, bool, bool, bool, bool);

void zmem_write_value(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, bool, bool, bool);

void zmem_read_cap(struct zMemoryOpResultzIRCapabilityzK *rop, uint64_t, bool, bool, bool);

bool zmem_read_cap_revoked(uint64_t);

void zmem_write_ea_cap(struct zMemoryOpResultzIuzK *rop, uint64_t, bool, bool, bool);

void zmem_write_cap(struct zMemoryOpResultzIozK *rop, uint64_t, struct zCapability, bool, bool, bool);

struct zPTE_Bits zMk_PTE_Bits(uint64_t);

uint64_t z_get_PTE_Bits_A(struct zPTE_Bits);

struct zPTE_Bits z_update_PTE_Bits_A(struct zPTE_Bits, uint64_t);

uint64_t z_get_PTE_Bits_D(struct zPTE_Bits);

struct zPTE_Bits z_update_PTE_Bits_D(struct zPTE_Bits, uint64_t);

uint64_t z_get_PTE_Bits_G(struct zPTE_Bits);

uint64_t z_get_PTE_Bits_R(struct zPTE_Bits);

uint64_t z_get_PTE_Bits_U(struct zPTE_Bits);

uint64_t z_get_PTE_Bits_V(struct zPTE_Bits);

uint64_t z_get_PTE_Bits_W(struct zPTE_Bits);

uint64_t z_get_PTE_Bits_X(struct zPTE_Bits);

struct zExt_PTE_Bits zMk_Ext_PTE_Bits(uint64_t);

uint64_t z_get_Ext_PTE_Bits_CapRead(struct zExt_PTE_Bits);

uint64_t z_get_Ext_PTE_Bits_CapWrite(struct zExt_PTE_Bits);

void create_letbind_49(void);
void kill_letbind_49(void);


bool zisPTEPtr(uint64_t, uint64_t);

bool zisInvalidPTE(uint64_t, uint64_t);

void zcheckPTEPermission(struct zPTE_Check *rop, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, bool, bool, struct zPTE_Bits, uint64_t, struct zext_ptw);

void zupdate_PTE_Bits(struct zoptionzIz8RPTE_BitszCbz9zK *rop, struct zPTE_Bits, struct zAccessTypezIEext_access_typez5zK, uint64_t);

void zext_get_ptw_error(struct zPTW_Error *rop, enum zext_ptw_fail);

void ztranslationException(struct zExceptionType *rop, struct zAccessTypezIEext_access_typez5zK, struct zPTW_Error);

void create_letbind_50(void);
void kill_letbind_50(void);


uint64_t zcurAsid32(uint64_t);

uint64_t zcurPTB32(uint64_t);

void create_letbind_51(void);
void kill_letbind_51(void);


void create_letbind_52(void);
void kill_letbind_52(void);


void create_letbind_53(void);
void kill_letbind_53(void);


void create_letbind_54(void);
void kill_letbind_54(void);


struct zSV32_Vaddr zMk_SV32_Vaddr(uint64_t);

uint64_t z_get_SV32_Vaddr_PgOfs(struct zSV32_Vaddr);

uint64_t z_get_SV32_Vaddr_VPNi(struct zSV32_Vaddr);

struct zSV32_PTE zMk_SV32_PTE(uint64_t);

uint64_t z_get_SV32_PTE_BITS(struct zSV32_PTE);

struct zSV32_PTE z_update_SV32_PTE_BITS(struct zSV32_PTE, uint64_t);

uint64_t z_get_SV32_PTE_PPNi(struct zSV32_PTE);

void create_letbind_55(void);
void kill_letbind_55(void);


void create_letbind_56(void);
void kill_letbind_56(void);


void create_letbind_57(void);
void kill_letbind_57(void);


void create_letbind_58(void);
void kill_letbind_58(void);


void create_letbind_59(void);
void kill_letbind_59(void);


void create_letbind_60(void);
void kill_letbind_60(void);


void create_letbind_61(void);
void kill_letbind_61(void);


void create_letbind_62(void);
void kill_letbind_62(void);


void zmake_TLB_Entry(struct zTLB_Entry *rop, lbits, bool, lbits, lbits, lbits, sail_int, lbits, sail_int);

bool zmatch_TLB_Entry(struct zTLB_Entry, lbits, lbits);

bool zflush_TLB_Entry(struct zTLB_Entry, struct zoptionzIbzK, struct zoptionzIbzK);

uint64_t zto_phys_addr(uint64_t);

void zwalk32(struct zPTW_ResultzIbzCRSV32_PTEzK *rop, uint64_t, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, bool, bool, uint64_t, sail_int, bool, struct zext_ptw);

void zlookup_TLB32(struct zoptionzIz8izCRTLB_Entryz9zK *rop, uint64_t, uint64_t);

unit zadd_to_TLB32(uint64_t, uint64_t, uint64_t, struct zSV32_PTE, uint64_t, sail_int, bool);

unit zwrite_TLB32(sail_int, struct zTLB_Entry);

unit zflush_TLB32(struct zoptionzIbzK, struct zoptionzIbzK);

void ztranslate32(struct zTR_ResultzIbzCUPTW_ErrorzK *rop, uint64_t, uint64_t, uint64_t, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege, bool, bool, sail_int, struct zext_ptw);

unit zinit_vmem_sv32(unit);

uint64_t zlegalizze_satp(enum zArchitecture, uint64_t, uint64_t);

enum zSATPMode ztranslationMode(enum zPrivilege);

void ztranslateAddr_priv(struct zTR_ResultzIbzCUExceptionTypezK *rop, uint64_t, struct zAccessTypezIEext_access_typez5zK, enum zPrivilege);

void ztranslateAddr(struct zTR_ResultzIbzCUExceptionTypezK *rop, uint64_t, struct zAccessTypezIEext_access_typez5zK);

unit zflush_TLB(struct zoptionzIbzK, struct zoptionzIbzK);

unit zinit_vmem(unit);

enum zRetired zexecute(struct zast);

void zassembly_forwards(sail_string *rop, struct zast);

void zencdec_backwards(struct zast *rop, uint64_t);

void zencdec_compressed_backwards(struct zast *rop, uint64_t);

enum zuop zencdec_uop_backwards(uint64_t);

bool zencdec_uop_backwards_matches(uint64_t);

enum zuop zencdec_uop_backwards_infallible(uint64_t);

void zutype_mnemonic_forwards(sail_string *rop, enum zuop);

void zutype_mnemonic_forwards_infallible(sail_string *rop, enum zuop);

enum zbop zencdec_bop_backwards(uint64_t);

bool zencdec_bop_backwards_matches(uint64_t);

enum zbop zencdec_bop_backwards_infallible(uint64_t);

void zbtype_mnemonic_forwards(sail_string *rop, enum zbop);

void zbtype_mnemonic_forwards_infallible(sail_string *rop, enum zbop);

enum ziop zencdec_iop_backwards(uint64_t);

bool zencdec_iop_backwards_matches(uint64_t);

enum ziop zencdec_iop_backwards_infallible(uint64_t);

void zitype_mnemonic_forwards(sail_string *rop, enum ziop);

void zitype_mnemonic_forwards_infallible(sail_string *rop, enum ziop);

void zshiftiop_mnemonic_forwards(sail_string *rop, enum zsop);

void zshiftiop_mnemonic_forwards_infallible(sail_string *rop, enum zsop);

void zrtype_mnemonic_forwards(sail_string *rop, enum zrop);

void zrtype_mnemonic_forwards_infallible(sail_string *rop, enum zrop);

void zextend_value(struct zMemoryOpResultzIbzK *rop, bool, struct zMemoryOpResultzIbzK);

enum zRetired zprocess_load(uint64_t, uint64_t, struct zMemoryOpResultzIbzK, bool);

bool zcheck_misaligned(uint64_t, enum zword_width);

void zmaybe_aq_forwards(sail_string *rop, bool);

void zmaybe_aq_forwards_infallible(sail_string *rop, bool);

void zmaybe_rl_forwards(sail_string *rop, bool);

void zmaybe_rl_forwards_infallible(sail_string *rop, bool);

void zmaybe_u_forwards(sail_string *rop, bool);

void zmaybe_u_forwards_infallible(sail_string *rop, bool);

void zrtypew_mnemonic_forwards(sail_string *rop, enum zropw);

void zrtypew_mnemonic_forwards_infallible(sail_string *rop, enum zropw);

void zshiftiwop_mnemonic_forwards(sail_string *rop, enum zsopw);

void zshiftiwop_mnemonic_forwards_infallible(sail_string *rop, enum zsopw);

uint64_t zeffective_fence_set(uint64_t, bool);

void zbit_maybe_r_forwards(sail_string *rop, uint64_t);

void zbit_maybe_r_forwards_infallible(sail_string *rop, uint64_t);

void zbit_maybe_w_forwards(sail_string *rop, uint64_t);

void zbit_maybe_w_forwards_infallible(sail_string *rop, uint64_t);

void zbit_maybe_i_forwards(sail_string *rop, uint64_t);

void zbit_maybe_i_forwards_infallible(sail_string *rop, uint64_t);

void zbit_maybe_o_forwards(sail_string *rop, uint64_t);

void zbit_maybe_o_forwards_infallible(sail_string *rop, uint64_t);

void zfence_bits_forwards(sail_string *rop, uint64_t);

void zfence_bits_forwards_infallible(sail_string *rop, uint64_t);

struct ztuple_z8z5boolzCz0z5boolzCz0z5boolz9 zencdec_mul_op_backwards(uint64_t);

bool zencdec_mul_op_backwards_matches(uint64_t);

struct ztuple_z8z5boolzCz0z5boolzCz0z5boolz9 zencdec_mul_op_backwards_infallible(uint64_t);

void zmul_mnemonic_forwards(sail_string *rop, struct ztuple_z8z5boolzCz0z5boolzCz0z5boolz9);

void zmul_mnemonic_forwards_infallible(sail_string *rop, struct ztuple_z8z5boolzCz0z5boolzCz0z5boolz9);

void zmaybe_not_u_forwards(sail_string *rop, bool);

void zmaybe_not_u_forwards_infallible(sail_string *rop, bool);

enum zcsrop zencdec_csrop_backwards(uint64_t);

bool zencdec_csrop_backwards_matches(uint64_t);

enum zcsrop zencdec_csrop_backwards_infallible(uint64_t);

uint64_t zreadCSR(uint64_t);

unit zwriteCSR(uint64_t, uint64_t);

unit zrvfi_rCSR(uint64_t, uint64_t);

unit zrvfi_wCSR(uint64_t, uint64_t);

void zcsr_mnemonic_forwards(sail_string *rop, enum zcsrop);

void zcsr_mnemonic_forwards_infallible(sail_string *rop, enum zcsrop);

void zzzba_rtypeuw_mnemonic_forwards(sail_string *rop, enum zbropw_zzba);

void zzzba_rtypeuw_mnemonic_forwards_infallible(sail_string *rop, enum zbropw_zzba);

void zzzba_rtype_mnemonic_forwards(sail_string *rop, enum zbrop_zzba);

void zzzba_rtype_mnemonic_forwards_infallible(sail_string *rop, enum zbrop_zzba);

void zzzbb_rtypew_mnemonic_forwards(sail_string *rop, enum zbropw_zzbb);

void zzzbb_rtypew_mnemonic_forwards_infallible(sail_string *rop, enum zbropw_zzbb);

void zzzbb_rtype_mnemonic_forwards(sail_string *rop, enum zbrop_zzbb);

void zzzbb_rtype_mnemonic_forwards_infallible(sail_string *rop, enum zbrop_zzbb);

void zzzbb_extop_mnemonic_forwards(sail_string *rop, enum zextop_zzbb);

void zzzbb_extop_mnemonic_forwards_infallible(sail_string *rop, enum zextop_zzbb);

void zzzbs_iop_mnemonic_forwards(sail_string *rop, enum zbiop_zzbs);

void zzzbs_iop_mnemonic_forwards_infallible(sail_string *rop, enum zbiop_zzbs);

void zzzbs_rtype_mnemonic_forwards(sail_string *rop, enum zbrop_zzbs);

void zzzbs_rtype_mnemonic_forwards_infallible(sail_string *rop, enum zbrop_zzbs);

void zzzbkb_rtype_mnemonic_forwards(sail_string *rop, enum zbrop_zzbkb);

void zzzbkb_rtype_mnemonic_forwards_infallible(sail_string *rop, enum zbrop_zzbkb);

void zencdec_capmode_backwards(struct zast *rop, uint64_t);

void zencdec_compressed_capmode_backwards(struct zast *rop, uint64_t);

unit zrvfi_rSCR(uint64_t, uint64_t, bool);

unit zrvfi_wSCR(uint64_t, uint64_t, bool);

void zencdec_capmode_backwards_infallible(struct zast *rop, uint64_t);

void zencdec_compressed_capmode_backwards_infallible(struct zast *rop, uint64_t);

void zencdec_backwards_infallible(struct zast *rop, uint64_t);

void zencdec_compressed_backwards_infallible(struct zast *rop, uint64_t);

void zassembly_forwards_infallible(sail_string *rop, struct zast);

void zprint_insn(sail_string *rop, struct zast);

void zext_fetch_hook(struct zFetchResult *rop, struct zFetchResult);

unit zext_post_step_hook(unit);

unit zext_init(unit);

void zext_decode_compressed(struct zast *rop, uint64_t);

void zext_decode(struct zast *rop, uint64_t);

void zfetch(struct zFetchResult *rop, unit);

enum zRetired ztry_execute(struct zast);

bool zstep(sail_int);

unit zloop(unit);

unit zinit_model(unit);

unit zmain(unit);

unit zinitializze_registers(unit);

extern struct zexception *current_exception;

extern bool have_exception;

extern sail_string *throw_location;

// register zelen
extern uint64_t zelen;

// register zvlen
extern uint64_t zvlen;

// register zrvfi_instruction
extern struct zRVFI_DII_Instruction_Packet zrvfi_instruction;

// register zrvfi_inst_data
extern struct zRVFI_DII_Execution_Packet_InstMetaData zrvfi_inst_data;

// register zrvfi_pc_data
extern struct zRVFI_DII_Execution_Packet_PC zrvfi_pc_data;

// register zrvfi_int_data
extern struct zRVFI_DII_Execution_Packet_Ext_Integer zrvfi_int_data;

// register zrvfi_int_data_present
extern bool zrvfi_int_data_present;

// register zrvfi_mem_data
extern struct zRVFI_DII_Execution_Packet_Ext_MemAccess zrvfi_mem_data;

// register zrvfi_mem_data_present
extern bool zrvfi_mem_data_present;

// register zrvfi_csr_data
extern struct zRVFI_DII_Execution_Packet_Ext_CSR zrvfi_csr_data;

// register zrvfi_csr_data_present
extern bool zrvfi_csr_data_present;

// register zrvfi_cheri_data
extern struct zRVFI_DII_Execution_Packet_Ext_CHERI zrvfi_cheri_data;

// register zrvfi_cheri_data_present
extern bool zrvfi_cheri_data_present;

// register zrvfi_cheri_scr_data
extern struct zRVFI_DII_Execution_Packet_Ext_CHERI_SCR zrvfi_cheri_scr_data;

// register zrvfi_cheri_scr_data_present
extern bool zrvfi_cheri_scr_data_present;

// register zPC
extern uint64_t zPC;

// register znextPC
extern uint64_t znextPC;

// register zinstbits
extern uint64_t zinstbits;

// register zx1
extern struct zCapability zx1;

// register zx2
extern struct zCapability zx2;

// register zx3
extern struct zCapability zx3;

// register zx4
extern struct zCapability zx4;

// register zx5
extern struct zCapability zx5;

// register zx6
extern struct zCapability zx6;

// register zx7
extern struct zCapability zx7;

// register zx8
extern struct zCapability zx8;

// register zx9
extern struct zCapability zx9;

// register zx10
extern struct zCapability zx10;

// register zx11
extern struct zCapability zx11;

// register zx12
extern struct zCapability zx12;

// register zx13
extern struct zCapability zx13;

// register zx14
extern struct zCapability zx14;

// register zx15
extern struct zCapability zx15;

// register zcur_privilege
extern enum zPrivilege zcur_privilege;

// register zcur_inst
extern uint64_t zcur_inst;

// register zmisa
extern struct zMisa zmisa;

// register zmstatush
extern struct zMstatush zmstatush;

// register zmstatus
extern struct zMstatus zmstatus;

// register zmip
extern struct zMinterrupts zmip;

// register zmie
extern struct zMinterrupts zmie;

// register zmideleg
extern struct zMinterrupts zmideleg;

// register zmedeleg
extern struct zMedeleg zmedeleg;

// register zmtvec
extern struct zMtvec zmtvec;

// register zmcause
extern struct zMcause zmcause;

// register zmepc
extern uint64_t zmepc;

// register zmtval
extern uint64_t zmtval;

// register zmscratch
extern uint64_t zmscratch;

// register zmcounteren
extern struct zCounteren zmcounteren;

// register zscounteren
extern struct zCounteren zscounteren;

// register zmcountinhibit
extern struct zCounterin zmcountinhibit;

// register zmcycle
extern uint64_t zmcycle;

// register zmtime
extern uint64_t zmtime;

// register zminstret
extern uint64_t zminstret;

// register zminstret_increment
extern bool zminstret_increment;

// register zmvendorid
extern uint64_t zmvendorid;

// register zmimpid
extern uint64_t zmimpid;

// register zmarchid
extern uint64_t zmarchid;

// register zmhartid
extern uint64_t zmhartid;

// register zsedeleg
extern struct zSedeleg zsedeleg;

// register zsideleg
extern struct zSinterrupts zsideleg;

// register zstvec
extern struct zMtvec zstvec;

// register zsscratch
extern uint64_t zsscratch;

// register zsepc
extern uint64_t zsepc;

// register zscause
extern struct zMcause zscause;

// register zstval
extern uint64_t zstval;

// register ztselect
extern uint64_t ztselect;

// register zmenvcfg
extern struct zEnvcfg zmenvcfg;

// register zsenvcfg
extern struct zEnvcfg zsenvcfg;

// register zvstart
extern uint64_t zvstart;

// register zvxsat
extern uint64_t zvxsat;

// register zvxrm
extern uint64_t zvxrm;

// register zvl
extern uint64_t zvl;

// register zvlenb
extern uint64_t zvlenb;

// register zvtype
extern struct zVtype zvtype;

// register zpmpcfg_n
extern zz5vecz8z5structz0zzPmpcfg_entz9 zpmpcfg_n;

// register zpmpaddr_n
extern zz5vecz8z5bv32z9 zpmpaddr_n;

// register zmccsr
extern struct zccsr zmccsr;

// register zsccsr
extern struct zccsr zsccsr;

// register zuccsr
extern struct zccsr zuccsr;

// register zMSHWMB
extern uint64_t zMSHWMB;

// register zMSHWM
extern uint64_t zMSHWM;

// register zPCC
extern struct zCapability zPCC;

// register znextPCC
extern struct zCapability znextPCC;

// register zMTCC
extern struct zCapability zMTCC;

// register zMTDC
extern struct zCapability zMTDC;

// register zMScratchC
extern struct zCapability zMScratchC;

// register zMEPCC
extern struct zCapability zMEPCC;

// register zvr0
extern lbits zvr0;

// register zvr1
extern lbits zvr1;

// register zvr2
extern lbits zvr2;

// register zvr3
extern lbits zvr3;

// register zvr4
extern lbits zvr4;

// register zvr5
extern lbits zvr5;

// register zvr6
extern lbits zvr6;

// register zvr7
extern lbits zvr7;

// register zvr8
extern lbits zvr8;

// register zvr9
extern lbits zvr9;

// register zvr10
extern lbits zvr10;

// register zvr11
extern lbits zvr11;

// register zvr12
extern lbits zvr12;

// register zvr13
extern lbits zvr13;

// register zvr14
extern lbits zvr14;

// register zvr15
extern lbits zvr15;

// register zvr16
extern lbits zvr16;

// register zvr17
extern lbits zvr17;

// register zvr18
extern lbits zvr18;

// register zvr19
extern lbits zvr19;

// register zvr20
extern lbits zvr20;

// register zvr21
extern lbits zvr21;

// register zvr22
extern lbits zvr22;

// register zvr23
extern lbits zvr23;

// register zvr24
extern lbits zvr24;

// register zvr25
extern lbits zvr25;

// register zvr26
extern lbits zvr26;

// register zvr27
extern lbits zvr27;

// register zvr28
extern lbits zvr28;

// register zvr29
extern lbits zvr29;

// register zvr30
extern lbits zvr30;

// register zvr31
extern lbits zvr31;

// register zvcsr
extern struct zVcsr zvcsr;

// register zutvec
extern struct zMtvec zutvec;

// register zuscratch
extern uint64_t zuscratch;

// register zuepc
extern uint64_t zuepc;

// register zucause
extern struct zMcause zucause;

// register zutval
extern uint64_t zutval;

// register zmtimecmp
extern uint64_t zmtimecmp;

// register zhtif_tohost
extern uint64_t zhtif_tohost;

// register zhtif_done
extern bool zhtif_done;

// register zhtif_exit_code
extern uint64_t zhtif_exit_code;

// register zhtif_cmd_write
extern uint64_t zhtif_cmd_write;

// register zhtif_payload_writes
extern uint64_t zhtif_payload_writes;

// register zUART_DLAB
extern uint64_t zUART_DLAB;

// register ztlb32
extern struct zoptionzIRTLB_EntryzK ztlb32;

// register zsatp
extern uint64_t zsatp;



#ifdef __cplusplus
}
#endif
