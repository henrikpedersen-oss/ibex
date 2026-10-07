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

// enum sopw
enum zsopw { zRISCV_SLLIW, zRISCV_SRLIW, zRISCV_SRAIW };

// enum sop
enum zsop { zRISCV_SLLI, zRISCV_SRLI, zRISCV_SRAI };

// enum seed_opst
enum zseed_opst { zBIST, zES16, zWAIT, zDEAD };

// enum rounding_mode
enum zrounding_mode { zRM_RNE, zRM_RTZ, zRM_RDN, zRM_RUP, zRM_RMM, zRM_DYN };

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

// type abbreviation regtype
typedef uint64_t zregtype;

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

// union option<Erounding_mode%>
enum kind_zoptionzIErounding_modez5zK { Kind_zNonezIErounding_modez5zK, Kind_zSomezIErounding_modez5zK };

struct zoptionzIErounding_modez5zK {
  enum kind_zoptionzIErounding_modez5zK kind;
  union {
    struct { unit zNonezIErounding_modez5zK; };
    struct { enum zrounding_mode zSomezIErounding_modez5zK; };
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

// struct tuple_(%bv, %unit)
struct ztuple_z8z5bvzCz0z5unitz9 {
  lbits ztup0;
  unit ztup1;
};

// union option<(b,u)>
enum kind_zoptionzIz8bzCuz9zK { Kind_zNonezIz8bzCuz9zK, Kind_zSomezIz8bzCuz9zK };

struct zoptionzIz8bzCuz9zK {
  enum kind_zoptionzIz8bzCuz9zK kind;
  union {
    struct { unit zNonezIz8bzCuz9zK; };
    struct { struct ztuple_z8z5bvzCz0z5unitz9 zSomezIz8bzCuz9zK; };
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
typedef unit zmem_meta;

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

// type abbreviation fregtype
typedef uint64_t zfregtype;

// type abbreviation flenbits
typedef uint64_t zflenbits;

// enum f_un_rm_op_S
enum zf_un_rm_op_S { zFSQRT_S, zFCVT_W_S, zFCVT_WU_S, zFCVT_S_W, zFCVT_S_WU, zFCVT_L_S, zFCVT_LU_S, zFCVT_S_L, zFCVT_S_LU };

// enum f_un_rm_op_H
enum zf_un_rm_op_H { zFSQRT_H, zFCVT_W_H, zFCVT_WU_H, zFCVT_H_W, zFCVT_H_WU, zFCVT_H_S, zFCVT_H_D, zFCVT_S_H, zFCVT_D_H, zFCVT_L_H, zFCVT_LU_H, zFCVT_H_L, zFCVT_H_LU };

// enum f_un_rm_op_D
enum zf_un_rm_op_D { zFSQRT_D, zFCVT_W_D, zFCVT_WU_D, zFCVT_D_W, zFCVT_D_WU, zFCVT_S_D, zFCVT_D_S, zFCVT_L_D, zFCVT_LU_D, zFCVT_D_L, zFCVT_D_LU };

// enum f_un_op_S
enum zf_un_op_S { zFCLASS_S, zFMV_X_W, zFMV_W_X };

// enum f_un_op_H
enum zf_un_op_H { zFCLASS_H, zFMV_X_H, zFMV_H_X };

// enum f_un_op_D
enum zf_un_op_D { zFCLASS_D, zFMV_X_D, zFMV_D_X };

// enum f_madd_op_S
enum zf_madd_op_S { zFMADD_S, zFMSUB_S, zFNMSUB_S, zFNMADD_S };

// enum f_madd_op_H
enum zf_madd_op_H { zFMADD_H, zFMSUB_H, zFNMSUB_H, zFNMADD_H };

// enum f_madd_op_D
enum zf_madd_op_D { zFMADD_D, zFMSUB_D, zFNMSUB_D, zFNMADD_D };

// enum f_bin_rm_op_S
enum zf_bin_rm_op_S { zFADD_S, zFSUB_S, zFMUL_S, zFDIV_S };

// enum f_bin_rm_op_H
enum zf_bin_rm_op_H { zFADD_H, zFSUB_H, zFMUL_H, zFDIV_H };

// enum f_bin_rm_op_D
enum zf_bin_rm_op_D { zFADD_D, zFSUB_D, zFMUL_D, zFDIV_D };

// enum f_bin_op_S
enum zf_bin_op_S { zFSGNJ_S, zFSGNJN_S, zFSGNJX_S, zFMIN_S, zFMAX_S, zFEQ_S, zFLT_S, zFLE_S };

// enum f_bin_op_H
enum zf_bin_op_H { zFSGNJ_H, zFSGNJN_H, zFSGNJX_H, zFMIN_H, zFMAX_H, zFEQ_H, zFLT_H, zFLE_H };

// enum f_bin_op_D
enum zf_bin_op_D { zFSGNJ_D, zFSGNJN_D, zFSGNJX_D, zFMIN_D, zFMAX_D, zFEQ_D, zFLT_D, zFLE_D };

// enum extop_zbb
enum zextop_zzbb { zRISCV_SEXTB, zRISCV_SEXTH, zRISCV_ZEXTH };

// type abbreviation ext_ptw_fail
typedef unit zext_ptw_fail;

// type abbreviation ext_ptw_error
typedef unit zext_ptw_error;

// type abbreviation ext_ptw
typedef unit zext_ptw;

// type abbreviation ext_fetch_addr_error
typedef unit zext_fetch_addr_error;

// type abbreviation ext_exception
typedef unit zext_exception;

// type abbreviation ext_exc_type
typedef unit zext_exc_type;

// type abbreviation ext_data_addr_error
typedef unit zext_data_addr_error;

// type abbreviation ext_control_addr_error
typedef unit zext_control_addr_error;

// type abbreviation ext_access_type
typedef unit zext_access_type;

// type abbreviation extPte
typedef uint64_t zextPte;

// union exception
enum kind_zexception { Kind_zError_internal_error, Kind_zError_not_implemented };

struct zexception {
  enum kind_zexception kind;
  union {
    struct { unit zError_internal_error; };
    struct { sail_string zError_not_implemented; };
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

// type abbreviation bits_fflags
typedef uint64_t zbits_fflags;

// type abbreviation bit
typedef uint64_t zbit;

// enum biop_zbs
enum zbiop_zzbs { zRISCV_BCLRI, zRISCV_BEXTI, zRISCV_BINVI, zRISCV_BSETI };

// type abbreviation asid32
typedef uint64_t zasid32;

// type abbreviation arch_xlen
typedef uint64_t zarch_xlen;

// enum amoop
enum zamoop { zAMOSWAP, zAMOADD, zAMOXOR, zAMOAND, zAMOOR, zAMOMIN, zAMOMAX, zAMOMINU, zAMOMAXU };

// struct tuple_(%bv1, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

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

// struct tuple_(%bv21, %bv5)
struct ztuple_z8z5bv21zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv1, %bv5, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv3, %bv5, %bv5)
struct ztuple_z8z5bv3zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv4, %bv5, %bv5)
struct ztuple_z8z5bv4zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv5, %enum zrounding_mode, %bv5)
struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 {
  uint64_t ztup0;
  enum zrounding_mode ztup1;
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

// struct tuple_(%bv5, %bv5, %enum zf_un_op_D)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Dz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zf_un_op_D ztup2;
};

// struct tuple_(%bv5, %bv5, %enum zf_un_op_H)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Hz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zf_un_op_H ztup2;
};

// struct tuple_(%bv5, %bv5, %enum zf_un_op_S)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Sz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zf_un_op_S ztup2;
};

// struct tuple_(%bv5, %bv5, %enum zvmlsop)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzvmlsopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvmlsop ztup2;
};

// struct tuple_(%bv5, %bv5, %bv5)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 {
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

// struct tuple_(%enum zmmfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzmmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zmmfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvext2funct6, %bv1, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvext2funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 {
  enum zvext2funct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvext4funct6, %bv1, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvext4funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 {
  enum zvext4funct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvext8funct6, %bv1, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvext8funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 {
  enum zvext8funct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvimcfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvimcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvimcfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvimfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvimfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvimfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvimsfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvimsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvimsfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvvmcfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvvmcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvvmcfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvvmfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvvmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvvmfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvvmsfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvvmsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvvmsfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvxmcfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxmcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxmcfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvxmfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxmfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%enum zvxmsfunct6, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxmsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxmsfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv1, %bv5, %enum zvfnunary0, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfnunary0zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvfnunary0 ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv1, %bv5, %enum zvfunary0, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfunary0zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvfunary0 ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv1, %bv5, %enum zvfunary1, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfunary1zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvfunary1 ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv1, %bv5, %enum zvfwunary0, %bv5)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfwunary0zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvfwunary0 ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv2, %bv5, %bv5, %bv5)
struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv3, %bv5, %enum zvlewidth, %bv5)
struct ztuple_z8z5bv3zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zvlewidth ztup2;
  uint64_t ztup3;
};

// struct tuple_(%bv5, %enum zrounding_mode, %bv5, %enum zf_un_rm_op_D)
struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Dz9 {
  uint64_t ztup0;
  enum zrounding_mode ztup1;
  uint64_t ztup2;
  enum zf_un_rm_op_D ztup3;
};

// struct tuple_(%bv5, %enum zrounding_mode, %bv5, %enum zf_un_rm_op_H)
struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Hz9 {
  uint64_t ztup0;
  enum zrounding_mode ztup1;
  uint64_t ztup2;
  enum zf_un_rm_op_H ztup3;
};

// struct tuple_(%bv5, %enum zrounding_mode, %bv5, %enum zf_un_rm_op_S)
struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Sz9 {
  uint64_t ztup0;
  enum zrounding_mode ztup1;
  uint64_t ztup2;
  enum zf_un_rm_op_S ztup3;
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

// struct tuple_(%bv5, %bv5, %bv5, %enum zf_bin_op_D)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Dz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zf_bin_op_D ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zf_bin_op_H)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Hz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zf_bin_op_H ztup3;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zf_bin_op_S)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Sz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zf_bin_op_S ztup3;
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

// struct tuple_(%bv5, %bv5, %bv5, %enum zzzicondop)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzzzzzicondopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zzzicondop ztup3;
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

// struct tuple_(%bv12, %bv5, %bv5, %enum zword_width)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zword_width ztup3;
};

// struct tuple_(%bv13, %bv5, %bv5, %enum zbop)
struct ztuple_z8z5bv13zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbopz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zbop ztup3;
};

// struct tuple_(%enum zfvffunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvffunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfvfmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvfmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvfmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfvfmfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvfmfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvfmfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfvvmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvvmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfvvmfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfvvmfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfvvmfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwffunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwffunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwvffunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwvffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwvffunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwvfmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwvfmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwvfmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zfwvvmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzfwvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zfwvvmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zmvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zmvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zmvvmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzmvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zmvvmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zmvxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzmvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zmvxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zmvxmafunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzmvxmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zmvxmafunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znifunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznifunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znifunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znisfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznisfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znisfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znvsfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznvsfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znvsfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum znxsfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zznxsfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum znxsfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zrfvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzrfvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zrfvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zrivvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzrivvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zrivvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zrmvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzrmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zrmvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvicmpfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvicmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvicmpfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvifunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvifunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvifunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvisgfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvisgfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvisgfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvvcmpfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvvcmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvvcmpfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvxcmpfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxcmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxcmpfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zvxsgfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvxsgfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zvxsgfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwmvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwmvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwmvxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwmvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwmvxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwvvfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwvvfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwvxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwvxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%enum zwxfunct6, %bv1, %bv5, %bv5, %bv5)
struct ztuple_z8z5enumz0zzwxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 {
  enum zwxfunct6 ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%bool, %bool, %bv5, %enum zword_width, %bv5)
struct ztuple_z8z5boolzCz0z5boolzCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 {
  bool ztup0;
  bool ztup1;
  uint64_t ztup2;
  enum zword_width ztup3;
  uint64_t ztup4;
};

// struct tuple_(%bv3, %bv1, %bv5, %enum zvlewidth, %bv5)
struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zvlewidth ztup3;
  uint64_t ztup4;
};

// struct tuple_(%bv4, %bv4, %bv4, %bv5, %bv5)
struct ztuple_z8z5bv4zCz0z5bv4zCz0z5bv4zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
};

// struct tuple_(%bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_bin_rm_op_D)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Dz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zrounding_mode ztup2;
  uint64_t ztup3;
  enum zf_bin_rm_op_D ztup4;
};

// struct tuple_(%bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_bin_rm_op_H)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Hz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zrounding_mode ztup2;
  uint64_t ztup3;
  enum zf_bin_rm_op_H ztup4;
};

// struct tuple_(%bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_bin_rm_op_S)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Sz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  enum zrounding_mode ztup2;
  uint64_t ztup3;
  enum zf_bin_rm_op_S ztup4;
};

// struct tuple_(%bv12, %bv5, %bv5, %bool, %enum zcsrop)
struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzcsropz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  bool ztup3;
  enum zcsrop ztup4;
};

// struct tuple_(%bool, %bool, %bv5, %bv5, %enum zword_width, %bv5)
struct ztuple_z8z5boolzCz0z5boolzCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 {
  bool ztup0;
  bool ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  enum zword_width ztup4;
  uint64_t ztup5;
};

// struct tuple_(%bv1, %bv1, %bv3, %bv3, %bv5, %bv5)
struct ztuple_z8z5bv1zCz0z5bv1zCz0z5bv3zCz0z5bv3zCz0z5bv5zCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
  uint64_t ztup5;
};

// struct tuple_(%bv3, %bv1, %bv5, %bv5, %enum zvlewidth, %bv5)
struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  enum zvlewidth ztup4;
  uint64_t ztup5;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_madd_op_D)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Dz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zrounding_mode ztup3;
  uint64_t ztup4;
  enum zf_madd_op_D ztup5;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_madd_op_H)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Hz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zrounding_mode ztup3;
  uint64_t ztup4;
  enum zf_madd_op_H ztup5;
};

// struct tuple_(%bv5, %bv5, %bv5, %enum zrounding_mode, %bv5, %enum zf_madd_op_S)
struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Sz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  enum zrounding_mode ztup3;
  uint64_t ztup4;
  enum zf_madd_op_S ztup5;
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

// struct tuple_(%enum zamoop, %bool, %bool, %bv5, %bv5, %enum zword_width, %bv5)
struct ztuple_z8z5enumz0zzamoopzCz0z5boolzCz0z5boolzCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 {
  enum zamoop ztup0;
  bool ztup1;
  bool ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
  enum zword_width ztup5;
  uint64_t ztup6;
};

// struct tuple_(%enum zvsetop, %bv1, %bv1, %bv3, %bv3, %bv5, %bv5)
struct ztuple_z8z5enumz0zzvsetopzCz0z5bv1zCz0z5bv1zCz0z5bv3zCz0z5bv3zCz0z5bv5zCz0z5bv5z9 {
  enum zvsetop ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  uint64_t ztup3;
  uint64_t ztup4;
  uint64_t ztup5;
  uint64_t ztup6;
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
enum kind_zast { Kind_zADDIW, Kind_zAES32DSI, Kind_zAES32DSMI, Kind_zAES32ESI, Kind_zAES32ESMI, Kind_zAES64DS, Kind_zAES64DSM, Kind_zAES64ES, Kind_zAES64ESM, Kind_zAES64IM, Kind_zAES64KS1I, Kind_zAES64KS2, Kind_zAMO, Kind_zBTYPE, Kind_zCSR, Kind_zC_ADD, Kind_zC_ADDI, Kind_zC_ADDI16SP, Kind_zC_ADDI4SPN, Kind_zC_ADDIW, Kind_zC_ADDI_HINT, Kind_zC_ADDW, Kind_zC_ADD_HINT, Kind_zC_AND, Kind_zC_ANDI, Kind_zC_BEQZ, Kind_zC_BNEZ, Kind_zC_EBREAK, Kind_zC_FLD, Kind_zC_FLDSP, Kind_zC_FLW, Kind_zC_FLWSP, Kind_zC_FSD, Kind_zC_FSDSP, Kind_zC_FSW, Kind_zC_FSWSP, Kind_zC_ILLEGAL, Kind_zC_J, Kind_zC_JAL, Kind_zC_JALR, Kind_zC_JR, Kind_zC_LD, Kind_zC_LDSP, Kind_zC_LI, Kind_zC_LI_HINT, Kind_zC_LUI, Kind_zC_LUI_HINT, Kind_zC_LW, Kind_zC_LWSP, Kind_zC_MV, Kind_zC_MV_HINT, Kind_zC_NOP, Kind_zC_NOP_HINT, Kind_zC_OR, Kind_zC_SD, Kind_zC_SDSP, Kind_zC_SLLI, Kind_zC_SLLI_HINT, Kind_zC_SRAI, Kind_zC_SRAI_HINT, Kind_zC_SRLI, Kind_zC_SRLI_HINT, Kind_zC_SUB, Kind_zC_SUBW, Kind_zC_SW, Kind_zC_SWSP, Kind_zC_XOR, Kind_zDIV, Kind_zDIVW, Kind_zEBREAK, Kind_zECALL, Kind_zFENCE, Kind_zFENCEI, Kind_zFENCEI_RESERVED, Kind_zFENCE_RESERVED, Kind_zFENCE_TSO, Kind_zFVFMATYPE, Kind_zFVFMTYPE, Kind_zFVFTYPE, Kind_zFVVMATYPE, Kind_zFVVMTYPE, Kind_zFVVTYPE, Kind_zFWFTYPE, Kind_zFWVFMATYPE, Kind_zFWVFTYPE, Kind_zFWVTYPE, Kind_zFWVVMATYPE, Kind_zFWVVTYPE, Kind_zF_BIN_RM_TYPE_D, Kind_zF_BIN_RM_TYPE_H, Kind_zF_BIN_RM_TYPE_S, Kind_zF_BIN_TYPE_D, Kind_zF_BIN_TYPE_H, Kind_zF_BIN_TYPE_S, Kind_zF_MADD_TYPE_D, Kind_zF_MADD_TYPE_H, Kind_zF_MADD_TYPE_S, Kind_zF_UN_RM_TYPE_D, Kind_zF_UN_RM_TYPE_H, Kind_zF_UN_RM_TYPE_S, Kind_zF_UN_TYPE_D, Kind_zF_UN_TYPE_H, Kind_zF_UN_TYPE_S, Kind_zILLEGAL, Kind_zITYPE, Kind_zLOAD, Kind_zLOADRES, Kind_zLOAD_FP, Kind_zMASKTYPEI, Kind_zMASKTYPEV, Kind_zMASKTYPEX, Kind_zMMTYPE, Kind_zMOVETYPEI, Kind_zMOVETYPEV, Kind_zMOVETYPEX, Kind_zMRET, Kind_zMUL, Kind_zMULW, Kind_zMVVCOMPRESS, Kind_zMVVMATYPE, Kind_zMVVTYPE, Kind_zMVXMATYPE, Kind_zMVXTYPE, Kind_zNISTYPE, Kind_zNITYPE, Kind_zNVSTYPE, Kind_zNVTYPE, Kind_zNXSTYPE, Kind_zNXTYPE, Kind_zREM, Kind_zREMW, Kind_zRFVVTYPE, Kind_zRISCV_BREV8, Kind_zRISCV_CLMUL, Kind_zRISCV_CLMULH, Kind_zRISCV_CLMULR, Kind_zRISCV_CLZ, Kind_zRISCV_CLZW, Kind_zRISCV_CPOP, Kind_zRISCV_CPOPW, Kind_zRISCV_CTZ, Kind_zRISCV_CTZW, Kind_zRISCV_FCVTMOD_W_D, Kind_zRISCV_FLEQ_D, Kind_zRISCV_FLEQ_H, Kind_zRISCV_FLEQ_S, Kind_zRISCV_FLI_D, Kind_zRISCV_FLI_H, Kind_zRISCV_FLI_S, Kind_zRISCV_FLTQ_D, Kind_zRISCV_FLTQ_H, Kind_zRISCV_FLTQ_S, Kind_zRISCV_FMAXM_D, Kind_zRISCV_FMAXM_H, Kind_zRISCV_FMAXM_S, Kind_zRISCV_FMINM_D, Kind_zRISCV_FMINM_H, Kind_zRISCV_FMINM_S, Kind_zRISCV_FMVH_X_D, Kind_zRISCV_FMVP_D_X, Kind_zRISCV_FROUNDNX_D, Kind_zRISCV_FROUNDNX_H, Kind_zRISCV_FROUNDNX_S, Kind_zRISCV_FROUND_D, Kind_zRISCV_FROUND_H, Kind_zRISCV_FROUND_S, Kind_zRISCV_JAL, Kind_zRISCV_JALR, Kind_zRISCV_ORCB, Kind_zRISCV_REV8, Kind_zRISCV_RORI, Kind_zRISCV_RORIW, Kind_zRISCV_SLLIUW, Kind_zRISCV_UNZIP, Kind_zRISCV_XPERM4, Kind_zRISCV_XPERM8, Kind_zRISCV_ZIP, Kind_zRIVVTYPE, Kind_zRMVVTYPE, Kind_zRTYPE, Kind_zRTYPEW, Kind_zSFENCE_VMA, Kind_zSHA256SIG0, Kind_zSHA256SIG1, Kind_zSHA256SUM0, Kind_zSHA256SUM1, Kind_zSHA512SIG0, Kind_zSHA512SIG0H, Kind_zSHA512SIG0L, Kind_zSHA512SIG1, Kind_zSHA512SIG1H, Kind_zSHA512SIG1L, Kind_zSHA512SUM0, Kind_zSHA512SUM0R, Kind_zSHA512SUM1, Kind_zSHA512SUM1R, Kind_zSHIFTIOP, Kind_zSHIFTIWOP, Kind_zSM3P0, Kind_zSM3P1, Kind_zSM4ED, Kind_zSM4KS, Kind_zSRET, Kind_zSTORE, Kind_zSTORECON, Kind_zSTORE_FP, Kind_zURET, Kind_zUTYPE, Kind_zVCPOP_M, Kind_zVEXT2TYPE, Kind_zVEXT4TYPE, Kind_zVEXT8TYPE, Kind_zVFIRST_M, Kind_zVFMERGE, Kind_zVFMV, Kind_zVFMVFS, Kind_zVFMVSF, Kind_zVFNUNARY0, Kind_zVFUNARY0, Kind_zVFUNARY1, Kind_zVFWUNARY0, Kind_zVICMPTYPE, Kind_zVID_V, Kind_zVIMCTYPE, Kind_zVIMSTYPE, Kind_zVIMTYPE, Kind_zVIOTA_M, Kind_zVISG, Kind_zVITYPE, Kind_zVLOXSEGTYPE, Kind_zVLRETYPE, Kind_zVLSEGFFTYPE, Kind_zVLSEGTYPE, Kind_zVLSSEGTYPE, Kind_zVLUXSEGTYPE, Kind_zVMSBF_M, Kind_zVMSIF_M, Kind_zVMSOF_M, Kind_zVMTYPE, Kind_zVMVRTYPE, Kind_zVMVSX, Kind_zVMVXS, Kind_zVSETI_TYPE, Kind_zVSET_TYPE, Kind_zVSOXSEGTYPE, Kind_zVSRETYPE, Kind_zVSSEGTYPE, Kind_zVSSSEGTYPE, Kind_zVSUXSEGTYPE, Kind_zVVCMPTYPE, Kind_zVVMCTYPE, Kind_zVVMSTYPE, Kind_zVVMTYPE, Kind_zVVTYPE, Kind_zVXCMPTYPE, Kind_zVXMCTYPE, Kind_zVXMSTYPE, Kind_zVXMTYPE, Kind_zVXSG, Kind_zVXTYPE, Kind_zWFI, Kind_zWMVVTYPE, Kind_zWMVXTYPE, Kind_zWVTYPE, Kind_zWVVTYPE, Kind_zWVXTYPE, Kind_zWXTYPE, Kind_zZBA_RTYPE, Kind_zZBA_RTYPEUW, Kind_zZBB_EXTOP, Kind_zZBB_RTYPE, Kind_zZBB_RTYPEW, Kind_zZBKB_PACKW, Kind_zZBKB_RTYPE, Kind_zZBS_IOP, Kind_zZBS_RTYPE, Kind_zZICOND_RTYPE };

struct zast {
  enum kind_zast kind;
  union {
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5z9 zADDIW; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zAES32DSI; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zAES32DSMI; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zAES32ESI; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zAES32ESMI; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zAES64DS; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zAES64DSM; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zAES64ES; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zAES64ESM; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zAES64IM; };
    struct { struct ztuple_z8z5bv4zCz0z5bv5zCz0z5bv5z9 zAES64KS1I; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zAES64KS2; };
    struct { struct ztuple_z8z5enumz0zzamoopzCz0z5boolzCz0z5boolzCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 zAMO; };
    struct { struct ztuple_z8z5bv13zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbopz9 zBTYPE; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzcsropz9 zCSR; };
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
    struct { unit zC_EBREAK; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_FLD; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_FLDSP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_FLW; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_FLWSP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_FSD; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_FSDSP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv3zCz0z5bv3z9 zC_FSW; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5z9 zC_FSWSP; };
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
    struct { struct ztuple_z8z5enumz0zzfvfmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVFMATYPE; };
    struct { struct ztuple_z8z5enumz0zzfvfmfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVFMTYPE; };
    struct { struct ztuple_z8z5enumz0zzfvffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVFTYPE; };
    struct { struct ztuple_z8z5enumz0zzfvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVVMATYPE; };
    struct { struct ztuple_z8z5enumz0zzfvvmfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVVMTYPE; };
    struct { struct ztuple_z8z5enumz0zzfvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzfwffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWFTYPE; };
    struct { struct ztuple_z8z5enumz0zzfwvfmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWVFMATYPE; };
    struct { struct ztuple_z8z5enumz0zzfwvffunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWVFTYPE; };
    struct { struct ztuple_z8z5enumz0zzfwvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWVTYPE; };
    struct { struct ztuple_z8z5enumz0zzfwvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWVVMATYPE; };
    struct { struct ztuple_z8z5enumz0zzfwvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zFWVVTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Dz9 zF_BIN_RM_TYPE_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Hz9 zF_BIN_RM_TYPE_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_bin_rm_op_Sz9 zF_BIN_RM_TYPE_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Dz9 zF_BIN_TYPE_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Hz9 zF_BIN_TYPE_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzf_bin_op_Sz9 zF_BIN_TYPE_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Dz9 zF_MADD_TYPE_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Hz9 zF_MADD_TYPE_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_madd_op_Sz9 zF_MADD_TYPE_S; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Dz9 zF_UN_RM_TYPE_D; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Hz9 zF_UN_RM_TYPE_H; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5zCz0z5enumz0zzf_un_rm_op_Sz9 zF_UN_RM_TYPE_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Dz9 zF_UN_TYPE_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Hz9 zF_UN_TYPE_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzf_un_op_Sz9 zF_UN_TYPE_S; };
    struct { uint64_t zILLEGAL; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zziopz9 zITYPE; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 zLOAD; };
    struct { struct ztuple_z8z5boolzCz0z5boolzCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 zLOADRES; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthz9 zLOAD_FP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMASKTYPEI; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMASKTYPEV; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMASKTYPEX; };
    struct { struct ztuple_z8z5enumz0zzmmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zMMTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zMOVETYPEI; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zMOVETYPEV; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zMOVETYPEX; };
    struct { unit zMRET; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolzCz0z5boolzCz0z5boolz9 zMUL; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMULW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zMVVCOMPRESS; };
    struct { struct ztuple_z8z5enumz0zzmvvmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zMVVMATYPE; };
    struct { struct ztuple_z8z5enumz0zzmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zMVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzmvxmafunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zMVXMATYPE; };
    struct { struct ztuple_z8z5enumz0zzmvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zMVXTYPE; };
    struct { struct ztuple_z8z5enumz0zznisfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNISTYPE; };
    struct { struct ztuple_z8z5enumz0zznifunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNITYPE; };
    struct { struct ztuple_z8z5enumz0zznvsfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNVSTYPE; };
    struct { struct ztuple_z8z5enumz0zznvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNVTYPE; };
    struct { struct ztuple_z8z5enumz0zznxsfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNXSTYPE; };
    struct { struct ztuple_z8z5enumz0zznxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zNXTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zREM; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5boolz9 zREMW; };
    struct { struct ztuple_z8z5enumz0zzrfvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zRFVVTYPE; };
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
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_FCVTMOD_W_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLEQ_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLEQ_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLEQ_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_FLI_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_FLI_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_FLI_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLTQ_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLTQ_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FLTQ_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMAXM_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMAXM_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMAXM_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMINM_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMINM_H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMINM_S; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zRISCV_FMVH_X_D; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zRISCV_FMVP_D_X; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUNDNX_D; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUNDNX_H; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUNDNX_S; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUND_D; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUND_H; };
    struct { struct ztuple_z8z5bv5zCz0z5enumz0zzrounding_modezCz0z5bv5z9 zRISCV_FROUND_S; };
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
    struct { struct ztuple_z8z5enumz0zzrivvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zRIVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzrmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zRMVVTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropz9 zRTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzropwz9 zRTYPEW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSFENCE_VMA; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA256SIG0; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA256SIG1; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA256SUM0; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA256SUM1; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA512SIG0; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SIG0H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SIG0L; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA512SIG1; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SIG1H; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SIG1L; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA512SUM0; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SUM0R; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSHA512SUM1; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zSHA512SUM1R; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopz9 zSHIFTIOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzsopwz9 zSHIFTIWOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSM3P0; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zSM3P1; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zSM4ED; };
    struct { struct ztuple_z8z5bv2zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zSM4KS; };
    struct { unit zSRET; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5boolzCz0z5boolz9 zSTORE; };
    struct { struct ztuple_z8z5boolzCz0z5boolzCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthzCz0z5bv5z9 zSTORECON; };
    struct { struct ztuple_z8z5bv12zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzword_widthz9 zSTORE_FP; };
    struct { unit zURET; };
    struct { struct ztuple_z8z5bv20zCz0z5bv5zCz0z5enumz0zzuopz9 zUTYPE; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVCPOP_M; };
    struct { struct ztuple_z8z5enumz0zzvext2funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 zVEXT2TYPE; };
    struct { struct ztuple_z8z5enumz0zzvext4funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 zVEXT4TYPE; };
    struct { struct ztuple_z8z5enumz0zzvext8funct6zCz0z5bv1zCz0z5bv5zCz0z5bv5z9 zVEXT8TYPE; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVFIRST_M; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zVFMERGE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zVFMV; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zVFMVFS; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zVFMVSF; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfnunary0zCz0z5bv5z9 zVFNUNARY0; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfunary0zCz0z5bv5z9 zVFUNARY0; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfunary1zCz0z5bv5z9 zVFUNARY1; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5enumz0zzvfwunary0zCz0z5bv5z9 zVFWUNARY0; };
    struct { struct ztuple_z8z5enumz0zzvicmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVICMPTYPE; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5z9 zVID_V; };
    struct { struct ztuple_z8z5enumz0zzvimcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVIMCTYPE; };
    struct { struct ztuple_z8z5enumz0zzvimsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVIMSTYPE; };
    struct { struct ztuple_z8z5enumz0zzvimfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVIMTYPE; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVIOTA_M; };
    struct { struct ztuple_z8z5enumz0zzvisgfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVISG; };
    struct { struct ztuple_z8z5enumz0zzvifunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVITYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLOXSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLRETYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLSEGFFTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLSSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVLUXSEGTYPE; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVMSBF_M; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVMSIF_M; };
    struct { struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv5z9 zVMSOF_M; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzvmlsopz9 zVMTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zVMVRTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zVMVSX; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5z9 zVMVXS; };
    struct { struct ztuple_z8z5bv1zCz0z5bv1zCz0z5bv3zCz0z5bv3zCz0z5bv5zCz0z5bv5z9 zVSETI_TYPE; };
    struct { struct ztuple_z8z5enumz0zzvsetopzCz0z5bv1zCz0z5bv1zCz0z5bv3zCz0z5bv3zCz0z5bv5zCz0z5bv5z9 zVSET_TYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVSOXSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv5zCz0z5bv5z9 zVSRETYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVSSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVSSSEGTYPE; };
    struct { struct ztuple_z8z5bv3zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzvlewidthzCz0z5bv5z9 zVSUXSEGTYPE; };
    struct { struct ztuple_z8z5enumz0zzvvcmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVVCMPTYPE; };
    struct { struct ztuple_z8z5enumz0zzvvmcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVVMCTYPE; };
    struct { struct ztuple_z8z5enumz0zzvvmsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVVMSTYPE; };
    struct { struct ztuple_z8z5enumz0zzvvmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVVMTYPE; };
    struct { struct ztuple_z8z5enumz0zzvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzvxcmpfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXCMPTYPE; };
    struct { struct ztuple_z8z5enumz0zzvxmcfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXMCTYPE; };
    struct { struct ztuple_z8z5enumz0zzvxmsfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXMSTYPE; };
    struct { struct ztuple_z8z5enumz0zzvxmfunct6zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXMTYPE; };
    struct { struct ztuple_z8z5enumz0zzvxsgfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXSG; };
    struct { struct ztuple_z8z5enumz0zzvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zVXTYPE; };
    struct { unit zWFI; };
    struct { struct ztuple_z8z5enumz0zzwmvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWMVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzwmvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWMVXTYPE; };
    struct { struct ztuple_z8z5enumz0zzwvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWVTYPE; };
    struct { struct ztuple_z8z5enumz0zzwvvfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWVVTYPE; };
    struct { struct ztuple_z8z5enumz0zzwvxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWVXTYPE; };
    struct { struct ztuple_z8z5enumz0zzwxfunct6zCz0z5bv1zCz0z5bv5zCz0z5bv5zCz0z5bv5z9 zWXTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbaz9 zZBA_RTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbaz9 zZBA_RTYPEUW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5enumz0zzextop_zzzzbbz9 zZBB_EXTOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbbz9 zZBB_RTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbropw_zzzzbbz9 zZBB_RTYPEW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5z9 zZBKB_PACKW; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbkbz9 zZBKB_RTYPE; };
    struct { struct ztuple_z8z5bv6zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbiop_zzzzbsz9 zZBS_IOP; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzbrop_zzzzbsz9 zZBS_RTYPE; };
    struct { struct ztuple_z8z5bv5zCz0z5bv5zCz0z5bv5zCz0z5enumz0zzzzzzicondopz9 zZICOND_RTYPE; };
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

// struct SEnvcfg
struct zSEnvcfg {uint64_t zbits;};

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
    struct { unit zPTW_Ext_Error; };
    struct { unit zPTW_Invalid_Addr; };
    struct { unit zPTW_Invalid_PTE; };
    struct { unit zPTW_Misaligned; };
    struct { unit zPTW_No_Permission; };
    struct { unit zPTW_PTE_Update; };
  } variants;
};

// struct tuple_(%union zPTW_Error, %unit)
struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5unitz9 {
  struct zPTW_Error ztup0;
  unit ztup1;
};

// union TR_Result<b,UPTW_Error>
enum kind_zTR_ResultzIbzCUPTW_ErrorzK { Kind_zTR_AddresszIbzCUPTW_ErrorzK, Kind_zTR_FailurezIbzCUPTW_ErrorzK };

struct zTR_ResultzIbzCUPTW_ErrorzK {
  enum kind_zTR_ResultzIbzCUPTW_ErrorzK kind;
  union {
    struct { struct ztuple_z8z5bvzCz0z5unitz9 zTR_AddresszIbzCUPTW_ErrorzK; };
    struct { struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5unitz9 zTR_FailurezIbzCUPTW_ErrorzK; };
  } variants;
};

// struct tuple_(%bv, %struct zSV32_PTE, %bv, %i, %bool, %unit)
struct ztuple_z8z5bvzCz0z5structz0zzSV32_PTEzCz0z5bvzCz0z5izCz0z5boolzCz0z5unitz9 {
  lbits ztup0;
  struct zSV32_PTE ztup1;
  lbits ztup2;
  sail_int ztup3;
  bool ztup4;
  unit ztup5;
};

// union PTW_Result<b,RSV32_PTE>
enum kind_zPTW_ResultzIbzCRSV32_PTEzK { Kind_zPTW_FailurezIbzCRSV32_PTEzK, Kind_zPTW_SuccesszIbzCRSV32_PTEzK };

struct zPTW_ResultzIbzCRSV32_PTEzK {
  enum kind_zPTW_ResultzIbzCRSV32_PTEzK kind;
  union {
    struct { struct ztuple_z8z5unionz0zzPTW_ErrorzCz0z5unitz9 zPTW_FailurezIbzCRSV32_PTEzK; };
    struct { struct ztuple_z8z5bvzCz0z5structz0zzSV32_PTEzCz0z5bvzCz0z5izCz0z5boolzCz0z5unitz9 zPTW_SuccesszIbzCRSV32_PTEzK; };
  } variants;
};

// struct tuple_(%unit, %unit)
struct ztuple_z8z5unitzCz0z5unitz9 {
  unit ztup0;
  unit ztup1;
};

// union PTE_Check
enum kind_zPTE_Check { Kind_zPTE_Check_Failure, Kind_zPTE_Check_Success };

struct zPTE_Check {
  enum kind_zPTE_Check kind;
  union {
    struct { struct ztuple_z8z5unitzCz0z5unitz9 zPTE_Check_Failure; };
    struct { unit zPTE_Check_Success; };
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

// struct MEnvcfg
struct zMEnvcfg {uint64_t zbits;};

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

// struct Fcsr
struct zFcsr {uint64_t zbits;};

// union Ext_FetchAddr_Check<u>
enum kind_zExt_FetchAddr_CheckzIuzK { Kind_zExt_FetchAddr_ErrorzIuzK, Kind_zExt_FetchAddr_OKzIuzK };

struct zExt_FetchAddr_CheckzIuzK {
  enum kind_zExt_FetchAddr_CheckzIuzK kind;
  union {
    struct { unit zExt_FetchAddr_ErrorzIuzK; };
    struct { uint64_t zExt_FetchAddr_OKzIuzK; };
  } variants;
};

// union Ext_DataAddr_Check<u>
enum kind_zExt_DataAddr_CheckzIuzK { Kind_zExt_DataAddr_ErrorzIuzK, Kind_zExt_DataAddr_OKzIuzK };

struct zExt_DataAddr_CheckzIuzK {
  enum kind_zExt_DataAddr_CheckzIuzK kind;
  union {
    struct { unit zExt_DataAddr_ErrorzIuzK; };
    struct { uint64_t zExt_DataAddr_OKzIuzK; };
  } variants;
};

// union Ext_ControlAddr_Check<u>
enum kind_zExt_ControlAddr_CheckzIuzK { Kind_zExt_ControlAddr_ErrorzIuzK, Kind_zExt_ControlAddr_OKzIuzK };

struct zExt_ControlAddr_CheckzIuzK {
  enum kind_zExt_ControlAddr_CheckzIuzK kind;
  union {
    struct { unit zExt_ControlAddr_ErrorzIuzK; };
    struct { uint64_t zExt_ControlAddr_OKzIuzK; };
  } variants;
};

// enum ExtStatus
enum zExtStatus { zOff, zInitial, zClean, zDirty };

// union ExceptionType
enum kind_zExceptionType { Kind_zE_Breakpoint, Kind_zE_Extension, Kind_zE_Fetch_Access_Fault, Kind_zE_Fetch_Addr_Align, Kind_zE_Fetch_Page_Fault, Kind_zE_Illegal_Instr, Kind_zE_Load_Access_Fault, Kind_zE_Load_Addr_Align, Kind_zE_Load_Page_Fault, Kind_zE_M_EnvCall, Kind_zE_Reserved_10, Kind_zE_Reserved_14, Kind_zE_SAMO_Access_Fault, Kind_zE_SAMO_Addr_Align, Kind_zE_SAMO_Page_Fault, Kind_zE_S_EnvCall, Kind_zE_U_EnvCall };

struct zExceptionType {
  enum kind_zExceptionType kind;
  union {
    struct { unit zE_Breakpoint; };
    struct { unit zE_Extension; };
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

// struct tuple_(%union zExceptionType, %unit)
struct ztuple_z8z5unionz0zzExceptionTypezCz0z5unitz9 {
  struct zExceptionType ztup0;
  unit ztup1;
};

// union TR_Result<b,UExceptionType>
enum kind_zTR_ResultzIbzCUExceptionTypezK { Kind_zTR_AddresszIbzCUExceptionTypezK, Kind_zTR_FailurezIbzCUExceptionTypezK };

struct zTR_ResultzIbzCUExceptionTypezK {
  enum kind_zTR_ResultzIbzCUExceptionTypezK kind;
  union {
    struct { struct ztuple_z8z5bvzCz0z5unitz9 zTR_AddresszIbzCUExceptionTypezK; };
    struct { struct ztuple_z8z5unionz0zzExceptionTypezCz0z5unitz9 zTR_FailurezIbzCUExceptionTypezK; };
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

// union MemoryOpResult<(b,u)>
enum kind_zMemoryOpResultzIz8bzCuz9zK { Kind_zMemExceptionzIz8bzCuz9zK, Kind_zMemValuezIz8bzCuz9zK };

struct zMemoryOpResultzIz8bzCuz9zK {
  enum kind_zMemoryOpResultzIz8bzCuz9zK kind;
  union {
    struct { struct zExceptionType zMemExceptionzIz8bzCuz9zK; };
    struct { struct ztuple_z8z5bvzCz0z5unitz9 zMemValuezIz8bzCuz9zK; };
  } variants;
};

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
    struct { unit zF_Ext_Error; };
    struct { uint64_t zF_RVC; };
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

// struct Counterin
struct zCounterin {uint64_t zbits;};

// struct Counteren
struct zCounteren {uint64_t zbits;};

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

// union AccessType<u>
enum kind_zAccessTypezIuzK { Kind_zExecutezIuzK, Kind_zReadzIuzK, Kind_zReadWritezIuzK, Kind_zWritezIuzK };

struct zAccessTypezIuzK {
  enum kind_zAccessTypezIuzK kind;
  union {
    struct { unit zExecutezIuzK; };
    struct { unit zReadzIuzK; };
    struct { struct ztuple_z8z5unitzCz0z5unitz9 zReadWritezIuzK; };
    struct { unit zWritezIuzK; };
  } variants;
};

struct zz5vecz8z5sbv64z9 {
  size_t len;
  sbits *data;
};
typedef struct zz5vecz8z5sbv64z9 zz5vecz8z5sbv64z9;

struct zz5vecz8z5bvz9 {
  size_t len;
  lbits *data;
};
typedef struct zz5vecz8z5bvz9 zz5vecz8z5bvz9;

struct zz5vecz8z5boolz9 {
  size_t len;
  bool *data;
};
typedef struct zz5vecz8z5boolz9 zz5vecz8z5boolz9;

struct zz5vecz8z5vecz8z5bvz9z9 {
  size_t len;
  zz5vecz8z5bvz9 *data;
};
typedef struct zz5vecz8z5vecz8z5bvz9z9 zz5vecz8z5vecz8z5bvz9z9;

struct zz5vecz8z5bv16z9 {
  size_t len;
  uint64_t *data;
};
typedef struct zz5vecz8z5bv16z9 zz5vecz8z5bv16z9;

struct zz5vecz8z5bv8z9 {
  size_t len;
  uint64_t *data;
};
typedef struct zz5vecz8z5bv8z9 zz5vecz8z5bv8z9;

struct zz5vecz8z5bv5z9 {
  size_t len;
  uint64_t *data;
};
typedef struct zz5vecz8z5bv5z9 zz5vecz8z5bv5z9;

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

// struct tuple_(%bv32, %bv32)
struct ztuple_z8z5bv32zCz0z5bv32z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bv16)
struct ztuple_z8z5bv5zCz0z5bv16z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bv32)
struct ztuple_z8z5bv5zCz0z5bv32z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bv64)
struct ztuple_z8z5bv5zCz0z5bv64z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv5, %bool)
struct ztuple_z8z5bv5zCz0z5boolz9 {
  uint64_t ztup0;
  bool ztup1;
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

// struct tuple_(%union zAccessTypezIuzK, %union zoptionzIz8bzCuz9zK)
struct ztuple_z8z5unionz0zzAccessTypezzIuzzKzCz0z5unionz0zzoptionzzIzz8bzzCuzz9zzKz9 {
  struct zAccessTypezIuzK ztup0;
  struct zoptionzIz8bzCuz9zK ztup1;
};

// struct tuple_(%union zAccessTypezIuzK, %enum zPrivilege)
struct ztuple_z8z5unionz0zzAccessTypezzIuzzKzCz0z5enumz0zzPrivilegez9 {
  struct zAccessTypezIuzK ztup0;
  enum zPrivilege ztup1;
};

// struct tuple_(%struct zPTE_Bits, %bv10)
struct ztuple_z8z5structz0zzPTE_BitszCz0z5bv10z9 {
  struct zPTE_Bits ztup0;
  uint64_t ztup1;
};

// struct tuple_(%union zAccessTypezIuzK, %union zPTW_Error)
struct ztuple_z8z5unionz0zzAccessTypezzIuzzKzCz0z5unionz0zzPTW_Errorz9 {
  struct zAccessTypezIuzK ztup0;
  struct zPTW_Error ztup1;
};

// struct tuple_(%union zoptionzIbzK, %union zoptionzIbzK)
struct ztuple_z8z5unionz0zzoptionzzIbzzKzCz0z5unionz0zzoptionzzIbzzKz9 {
  struct zoptionzIbzK ztup0;
  struct zoptionzIbzK ztup1;
};

// struct tuple_(%bv34, %struct zSV32_PTE, %bv34, %i, %bool, %unit)
struct ztuple_z8z5bv34zCz0z5structz0zzSV32_PTEzCz0z5bv34zCz0z5izCz0z5boolzCz0z5unitz9 {
  uint64_t ztup0;
  struct zSV32_PTE ztup1;
  uint64_t ztup2;
  sail_int ztup3;
  bool ztup4;
  unit ztup5;
};

// struct tuple_(%i64, %struct zTLB_Entry)
struct ztuple_z8z5i64zCz0z5structz0zzTLB_Entryz9 {
  int64_t ztup0;
  struct zTLB_Entry ztup1;
};

// struct tuple_(%bv34, %unit)
struct ztuple_z8z5bv34zCz0z5unitz9 {
  uint64_t ztup0;
  unit ztup1;
};

// struct tuple_(%bv32, %unit)
struct ztuple_z8z5bv32zCz0z5unitz9 {
  uint64_t ztup0;
  unit ztup1;
};

// struct tuple_(%bv12, %i64)
struct ztuple_z8z5bv12zCz0z5i64z9 {
  uint64_t ztup0;
  int64_t ztup1;
};

// struct tuple_(%bv1, %bv8, %bv23)
struct ztuple_z8z5bv1zCz0z5bv8zCz0z5bv23z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bool, %bv5)
struct ztuple_z8z5boolzCz0z5bv5z9 {
  bool ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv1, %bv11, %bv52)
struct ztuple_z8z5bv1zCz0z5bv11zCz0z5bv52z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%bv1, %bv5, %bv10)
struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv10z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
};

// struct tuple_(%vec(%bv), %vec(%bool))
struct ztuple_z8z5vecz8z5bvz9zCz0z5vecz8z5boolz9z9 {
  zz5vecz8z5bvz9 ztup0;
  zz5vecz8z5boolz9 ztup1;
};

// struct tuple_(%vec(%bool), %vec(%bool))
struct ztuple_z8z5vecz8z5boolz9zCz0z5vecz8z5boolz9z9 {
  zz5vecz8z5boolz9 ztup0;
  zz5vecz8z5boolz9 ztup1;
};

// struct tuple_(%bv5, %sbv64)
struct ztuple_z8z5bv5zCz0z5sbv64z9 {
  uint64_t ztup0;
  sbits ztup1;
};

// struct tuple_(%bv5, %bv8)
struct ztuple_z8z5bv5zCz0z5bv8z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv64, %bv64)
struct ztuple_z8z5bv64zCz0z5bv64z9 {
  uint64_t ztup0;
  uint64_t ztup1;
};

// struct tuple_(%bv64, %bv64, %bv1, %i64, %i64)
struct ztuple_z8z5bv64zCz0z5bv64zCz0z5bv1zCz0z5i64zCz0z5i64z9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  int64_t ztup3;
  int64_t ztup4;
};

// struct tuple_(%bv64, %bv64, %bv1, %i, %i)
struct ztuple_z8z5bv64zCz0z5bv64zCz0z5bv1zCz0z5izCz0z5iz9 {
  uint64_t ztup0;
  uint64_t ztup1;
  uint64_t ztup2;
  sail_int ztup3;
  sail_int ztup4;
};

struct zz5vecz8z5iz9 {
  size_t len;
  sail_int *data;
};
typedef struct zz5vecz8z5iz9 zz5vecz8z5iz9;

// struct tuple_(%bool, %bv64)
struct ztuple_z8z5boolzCz0z5bv64z9 {
  bool ztup0;
  uint64_t ztup1;
};

// struct tuple_(%sbv64, %sbv64)
struct ztuple_z8z5sbv64zCz0z5sbv64z9 {
  sbits ztup0;
  sbits ztup1;
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

// struct tuple_(%bool, %bool, %enum zword_width)
struct ztuple_z8z5boolzCz0z5boolzCz0z5enumz0zzword_widthz9 {
  bool ztup0;
  bool ztup1;
  enum zword_width ztup2;
};

// struct tuple_(%enum zamoop, %bool, %bool, %enum zword_width)
struct ztuple_z8z5enumz0zzamoopzCz0z5boolzCz0z5boolzCz0z5enumz0zzword_widthz9 {
  enum zamoop ztup0;
  bool ztup1;
  bool ztup2;
  enum zword_width ztup3;
};

// struct tuple_(%enum zword_width, %i64)
struct ztuple_z8z5enumz0zzword_widthzCz0z5i64z9 {
  enum zword_width ztup0;
  int64_t ztup1;
};

// struct tuple_(%union zoptionzIEArchitecturez5zK, %bv1)
struct ztuple_z8z5unionz0zzoptionzzIEArchitecturezz5zzKzCz0z5bv1z9 {
  struct zoptionzIEArchitecturez5zK ztup0;
  uint64_t ztup1;
};

// struct tuple_(%vec(%sbv64), %vec(%bool))
struct ztuple_z8z5vecz8z5sbv64z9zCz0z5vecz8z5boolz9z9 {
  zz5vecz8z5sbv64z9 ztup0;
  zz5vecz8z5boolz9 ztup1;
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

bool zneq_anythingzIUAccessTypezIuzKzK(struct zAccessTypezIuzK, struct zAccessTypezIuzK);

bool zneq_anythingzIEPrivilegez5zK(enum zPrivilege, enum zPrivilege);

void zhex_bits_forwards(struct ztuple_z8z5izCz0z5stringz9 *rop, lbits);

bool zhex_bits_forwards_matches(lbits);

void zhex_bits_2_forwards(sail_string *rop, uint64_t);

void zhex_bits_2_forwards_infallible(sail_string *rop, uint64_t);

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

bool zz8operatorz0zIzJ_uz9(lbits, lbits);

bool zz8operatorz0zKzJ_uz9(lbits, lbits);

uint64_t zshift_right_arith32(uint64_t, uint64_t);

void zrotate_bits_right(lbits *rop, lbits, lbits);

void zrotate_bits_left(lbits *rop, lbits, lbits);

void zrotater(lbits *rop, lbits, sail_int);

void zrotatel(lbits *rop, lbits, sail_int);

uint64_t zreverse_bits_in_byte(uint64_t);

void zlog2(sail_int *rop, int64_t);

int64_t zget_elen_pow(unit);

int64_t zget_vlen_pow(unit);

void create_letbind_0(void);
void kill_letbind_0(void);


unit z__WriteRAM_Meta(uint64_t, sail_int, unit);

unit z__ReadRAM_Meta(uint64_t, sail_int);

bool zwrite_ram(enum zwrite_kind, uint64_t, int64_t, lbits, unit);

unit zwrite_ram_ea(enum zwrite_kind, uint64_t, int64_t);

void zread_ram(struct ztuple_z8z5bvzCz0z5unitz9 *rop, enum zread_kind, uint64_t, int64_t, bool);

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

void z_update_RVFI_DII_Execution_PacketV2_basic_data(struct zRVFI_DII_Execution_PacketV2 *rop, struct zRVFI_DII_Execution_PacketV2, lbits);

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

uint64_t zrvfi_encode_width_mask(int64_t);

unit zprint_rvfi_exec(unit);

void create_letbind_1(void);
void kill_letbind_1(void);


unit zext_translate_exception(unit);

uint64_t zext_exc_type_to_bits(unit);

int64_t znum_of_ext_exc_type(unit);

void zext_exc_type_to_str(sail_string *rop, unit);

void create_letbind_2(void);
void kill_letbind_2(void);


void create_letbind_3(void);
void kill_letbind_3(void);


void create_letbind_4(void);
void kill_letbind_4(void);


void create_letbind_5(void);
void kill_letbind_5(void);


uint64_t zcreg2reg_idx(uint64_t);

void create_letbind_6(void);
void kill_letbind_6(void);


void create_letbind_7(void);
void kill_letbind_7(void);


void create_letbind_8(void);
void kill_letbind_8(void);


void zarchitecture(struct zoptionzIEArchitecturez5zK *rop, uint64_t);

uint64_t zinternal_errorzIB32zK(const_sail_string, sail_int, const_sail_string);

uint64_t zinternal_errorzIB1zK(const_sail_string, sail_int, const_sail_string);

unit zinternal_errorzIuzK(const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUTR_ResultzIbzCUExceptionTypezKzK(struct zTR_ResultzIbzCUExceptionTypezK *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUPTE_CheckzK(struct zPTE_Check *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUMemoryOpResultzIbzKzK(struct zMemoryOpResultzIbzK *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUMemoryOpResultzIuzKzK(struct zMemoryOpResultzIuzK *rop, const_sail_string, sail_int, const_sail_string);

void zinternal_errorzIUMemoryOpResultzIozKzK(struct zMemoryOpResultzIozK *rop, const_sail_string, sail_int, const_sail_string);

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

void create_letbind_9(void);
void kill_letbind_9(void);


void create_letbind_10(void);
void kill_letbind_10(void);


void zaccessType_to_str(sail_string *rop, struct zAccessTypezIuzK);

void create_letbind_11(void);
void kill_letbind_11(void);


void zRegStr(sail_string *rop, uint64_t);

uint64_t zregval_from_reg(uint64_t);

uint64_t zregval_into_reg(uint64_t);

void create_letbind_12(void);
void kill_letbind_12(void);


void zFRegStr(sail_string *rop, uint64_t);

uint64_t zfregval_from_freg(uint64_t);

uint64_t zfregval_into_freg(uint64_t);

uint64_t zrX(int64_t);

unit zrvfi_wX(int64_t, uint64_t);

unit zwX(int64_t, uint64_t);

uint64_t zrX_bits(uint64_t);

unit zwX_bits(uint64_t, uint64_t);

void zreg_name_forwards(sail_string *rop, uint64_t);

void zreg_name_forwards_infallible(sail_string *rop, uint64_t);

void zcreg_name_forwards(sail_string *rop, uint64_t);

void zcreg_name_forwards_infallible(sail_string *rop, uint64_t);

unit zinit_base_regs(unit);

unit zset_next_pc(uint64_t);

unit ztick_pc(unit);

struct zMisa zundefined_Misa(unit);

struct zMisa zMk_Misa(uint64_t);

uint64_t z_get_Misa_A(struct zMisa);

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

uint64_t z_get_Misa_V(struct zMisa);

struct zMisa zlegalizze_misa(struct zMisa, uint64_t);

bool zhaveAtomics(unit);

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

enum zPrivilege zeffectivePrivilege(struct zAccessTypezIuzK, struct zMstatus, enum zPrivilege);

uint64_t zget_mstatus_SXL(struct zMstatus);

struct zMstatus zset_mstatus_SXL(struct zMstatus, uint64_t);

uint64_t zget_mstatus_UXL(struct zMstatus);

struct zMstatus zset_mstatus_UXL(struct zMstatus, uint64_t);

struct zMstatus zlegalizze_mstatus(struct zMstatus, uint64_t);

enum zArchitecture zcur_Architecture(unit);

bool zin32BitMode(unit);

bool zhaveFExt(unit);

bool zhaveDExt(unit);

bool zhaveZfh(unit);

bool zhaveVExt(unit);

bool zhaveZhinx(unit);

bool zhaveZfinx(unit);

bool zhaveZdinx(unit);

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

uint64_t z_get_Mtvec_Base(struct zMtvec);

uint64_t z_get_Mtvec_Mode(struct zMtvec);

struct zMtvec z_update_Mtvec_Mode(struct zMtvec, uint64_t);

struct zMtvec zlegalizze_tvec(struct zMtvec, uint64_t);

struct zMcause zundefined_Mcause(unit);

uint64_t z_get_Mcause_Cause(struct zMcause);

uint64_t z_get_Mcause_IsInterrupt(struct zMcause);

void ztvec_addr(struct zoptionzIbzK *rop, struct zMtvec, struct zMcause);

uint64_t zlegalizze_xepc(uint64_t);

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

struct zMEnvcfg zundefined_MEnvcfg(unit);

struct zMEnvcfg zMk_MEnvcfg(uint64_t);

uint64_t z_get_MEnvcfg_FIOM(struct zMEnvcfg);

struct zMEnvcfg z_update_MEnvcfg_FIOM(struct zMEnvcfg, uint64_t);

struct zSEnvcfg zundefined_SEnvcfg(unit);

struct zSEnvcfg zMk_SEnvcfg(uint64_t);

uint64_t z_get_SEnvcfg_FIOM(struct zSEnvcfg);

struct zSEnvcfg z_update_SEnvcfg_FIOM(struct zSEnvcfg, uint64_t);

struct zMEnvcfg zlegalizze_menvcfg(struct zMEnvcfg, uint64_t);

struct zSEnvcfg zlegalizze_senvcfg(struct zSEnvcfg, uint64_t);

bool zis_fiom_active(unit);

struct zVtype zundefined_Vtype(unit);

uint64_t z_get_Vtype_vill(struct zVtype);

uint64_t z_get_Vtype_vlmul(struct zVtype);

uint64_t z_get_Vtype_vma(struct zVtype);

uint64_t z_get_Vtype_vsew(struct zVtype);

uint64_t z_get_Vtype_vta(struct zVtype);

int64_t zget_sew_pow(unit);

int64_t zget_sew(unit);

int64_t zget_sew_bytes(unit);

int64_t zget_lmul_pow(unit);

enum zagtype zdecode_agtype(uint64_t);

enum zagtype zget_vtype_vma(unit);

enum zagtype zget_vtype_vta(unit);

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

bool zpmpCheckRWX(struct zPmpcfg_ent, struct zAccessTypezIuzK);

bool zpmpCheckPerms(struct zPmpcfg_ent, struct zAccessTypezIuzK, enum zPrivilege);

enum zpmpAddrMatch zpmpMatchAddr(uint64_t, uint64_t, struct zoptionzIz8bzCbz9zK);

enum zpmpMatch zpmpMatchEntry(uint64_t, uint64_t, struct zAccessTypezIuzK, enum zPrivilege, struct zPmpcfg_ent, uint64_t, uint64_t);

void zaccessToFault(struct zExceptionType *rop, struct zAccessTypezIuzK);

void zpmpCheck(struct zoptionzIUExceptionTypezK *rop, uint64_t, sail_int, struct zAccessTypezIuzK, enum zPrivilege);

unit zinit_pmp(unit);

unit zext_rvfi_init(unit);

bool zext_check_CSR(uint64_t, enum zPrivilege, bool);

void zext_check_phys_mem_read(struct zExt_PhysAddr_Check *rop, struct zAccessTypezIuzK, uint64_t, int64_t, bool, bool, bool, bool);

void zext_check_phys_mem_write(struct zExt_PhysAddr_Check *rop, enum zwrite_kind, uint64_t, int64_t, lbits, unit);

void zext_fetch_check_pc(struct zExt_FetchAddr_CheckzIuzK *rop, uint64_t, uint64_t);

unit zext_handle_fetch_check_error(unit);

void zext_control_check_addr(struct zExt_ControlAddr_CheckzIuzK *rop, uint64_t);

void zext_control_check_pc(struct zExt_ControlAddr_CheckzIuzK *rop, uint64_t);

unit zext_handle_control_check_error(unit);

void zext_data_get_addr(struct zExt_DataAddr_CheckzIuzK *rop, uint64_t, uint64_t, struct zAccessTypezIuzK, enum zword_width);

unit zext_handle_data_check_error(unit);

void zvreg_name_forwards(sail_string *rop, uint64_t);

void zvreg_name_forwards_infallible(sail_string *rop, uint64_t);

unit zdirty_v_context(unit);

unit zdirty_v_context_if_present(unit);

void zrV(lbits *rop, int64_t);

unit zwV(int64_t, lbits);

void zrV_bits(lbits *rop, uint64_t);

unit zwV_bits(uint64_t, lbits);

struct zVcsr zundefined_Vcsr(unit);

uint64_t z_get_Vcsr_vxrm(struct zVcsr);

uint64_t z_get_Vcsr_vxsat(struct zVcsr);

unit zext_write_vcsr(uint64_t, uint64_t);

void zget_num_elem(sail_int *rop, sail_int, sail_int);

void zread_single_vreg(zz5vecz8z5bvz9 *rop, sail_int, sail_int, uint64_t);

unit zwrite_single_vreg(sail_int, sail_int, uint64_t, zz5vecz8z5bvz9);

void zread_vreg(zz5vecz8z5bvz9 *rop, sail_int, sail_int, sail_int, uint64_t);

void zread_single_element(lbits *rop, int64_t, sail_int, uint64_t);

unit zwrite_vreg(sail_int, sail_int, sail_int, uint64_t, zz5vecz8z5bvz9);

unit zwrite_single_element(int64_t, sail_int, uint64_t, lbits);

void zread_vmask(zz5vecz8z5boolz9 *rop, sail_int, uint64_t, uint64_t);

void zread_vmask_carry(zz5vecz8z5boolz9 *rop, sail_int, uint64_t, uint64_t);

unit zwrite_vmask(sail_int, uint64_t, zz5vecz8z5boolz9);

void zcsr_name_map_forwards(sail_string *rop, uint64_t);

void zcsr_name(sail_string *rop, uint64_t);

bool zext_is_CSR_defined(uint64_t, enum zPrivilege);

void zext_read_CSR(struct zoptionzIbzK *rop, uint64_t);

void zext_write_CSR(struct zoptionzIbzK *rop, uint64_t, uint64_t);

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

uint64_t zset_xret_target(enum zPrivilege, uint64_t);

uint64_t zget_mtvec(unit);

uint64_t zget_stvec(unit);

uint64_t zget_utvec(unit);

uint64_t zset_mtvec(uint64_t);

uint64_t zset_stvec(uint64_t);

uint64_t zset_utvec(uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Add(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Sub(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Mul(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Div(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Add(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Sub(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Mul(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Div(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Add(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Sub(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Mul(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Div(uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16MulAdd(uint64_t, uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32MulAdd(uint64_t, uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64MulAdd(uint64_t, uint64_t, uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Sqrt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Sqrt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Sqrt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f16ToI32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f16ToUi32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_i32ToF16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_ui32ToF16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32ToI32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32ToUi32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_i32ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_ui32ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f32ToI64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f32ToUi64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_i64ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_ui64ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f64ToI32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f64ToUi32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_i32ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_ui32ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64ToI64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64ToUi64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_i64ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_ui64ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f16ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f16ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f32ToF64(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f32ToF16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f64ToF16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f64ToF32(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f16Lt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f16Lt_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f16Le(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f16Le_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f16Eq(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f32Lt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f32Lt_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f32Le(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f32Le_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f32Eq(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f64Lt(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f64Lt_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f64Le(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f64Le_quiet(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5boolz9 zriscv_f64Eq(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16roundToInt(uint64_t, uint64_t, bool);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32roundToInt(uint64_t, uint64_t, bool);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64roundToInt(uint64_t, uint64_t, bool);

uint64_t znan_box_H(uint64_t);

uint64_t znan_unbox_H(uint64_t);

uint64_t znan_box_S(uint64_t);

uint64_t znan_unbox_S(uint64_t);

unit zdirty_fd_context(unit);

unit zdirty_fd_context_if_present(unit);

uint64_t zrF(int64_t);

unit zwF(int64_t, uint64_t);

uint64_t zrF_bits(uint64_t);

unit zwF_bits(uint64_t, uint64_t);

uint64_t zrF_H(uint64_t);

unit zwF_H(uint64_t, uint64_t);

uint64_t zrF_S(uint64_t);

unit zwF_S(uint64_t, uint64_t);

uint64_t zrF_D(uint64_t);

unit zwF_D(uint64_t, uint64_t);

uint64_t zrF_or_X_H(uint64_t);

uint64_t zrF_or_X_S(uint64_t);

uint64_t zrF_or_X_D(uint64_t);

unit zwF_or_X_H(uint64_t, uint64_t);

unit zwF_or_X_S(uint64_t, uint64_t);

unit zwF_or_X_D(uint64_t, uint64_t);

void zfreg_name_forwards(sail_string *rop, uint64_t);

void zfreg_name_forwards_infallible(sail_string *rop, uint64_t);

void zfreg_or_reg_name_forwards(sail_string *rop, uint64_t);

void zfreg_or_reg_name_forwards_infallible(sail_string *rop, uint64_t);

unit zinit_fdext_regs(unit);

struct zFcsr zundefined_Fcsr(unit);

uint64_t z_get_Fcsr_FFLAGS(struct zFcsr);

uint64_t z_get_Fcsr_FRM(struct zFcsr);

unit zext_write_fcsr(uint64_t, uint64_t);

unit zaccrue_fflags(uint64_t);

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

void zMemoryOpResult_add_metazIbzK(struct zMemoryOpResultzIz8bzCuz9zK *rop, struct zMemoryOpResultzIbzK, unit);

void zMemoryOpResult_drop_metazIbzK(struct zMemoryOpResultzIbzK *rop, struct zMemoryOpResultzIz8bzCuz9zK);

bool zwithin_phys_mem(uint64_t, sail_int);

bool zwithin_clint(uint64_t, int64_t);

bool zwithin_htif_writable(uint64_t, int64_t);

bool zwithin_htif_readable(uint64_t, int64_t);

void create_letbind_13(void);
void kill_letbind_13(void);


void create_letbind_14(void);
void kill_letbind_14(void);


void create_letbind_15(void);
void kill_letbind_15(void);


void create_letbind_16(void);
void kill_letbind_16(void);


void create_letbind_17(void);
void kill_letbind_17(void);


void zclint_load(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIuzK, uint64_t, sail_int);

unit zclint_dispatch(unit);

void zclint_store(struct zMemoryOpResultzIozK *rop, uint64_t, sail_int, lbits);

unit ztick_clock(unit);

struct zhtif_cmd zMk_htif_cmd(uint64_t);

uint64_t z_get_htif_cmd_cmd(struct zhtif_cmd);

uint64_t z_get_htif_cmd_device(struct zhtif_cmd);

uint64_t z_get_htif_cmd_payload(struct zhtif_cmd);

unit zreset_htif(unit);

void zhtif_load(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIuzK, uint64_t, sail_int);

void zhtif_store(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, sbits);

unit zhtif_tick(unit);

bool zwithin_mmio_readable(uint64_t, int64_t);

bool zwithin_mmio_writable(uint64_t, int64_t);

void zmmio_read(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIuzK, uint64_t, int64_t);

void zmmio_write(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits);

unit zinit_platform(unit);

unit ztick_platform(unit);

unit zhandle_illegal(unit);

unit zplatform_wfi(unit);

bool zis_aligned_addr(uint64_t, sail_int);

void zread_kind_of_flags(struct zoptionzIEread_kindz5zK *rop, bool, bool, bool);

void zphys_mem_read(struct zMemoryOpResultzIz8bzCuz9zK *rop, struct zAccessTypezIuzK, uint64_t, int64_t, bool, bool, bool, bool);

void zchecked_mem_read(struct zMemoryOpResultzIz8bzCuz9zK *rop, struct zAccessTypezIuzK, uint64_t, int64_t, bool, bool, bool, bool);

void zpmp_mem_read(struct zMemoryOpResultzIz8bzCuz9zK *rop, struct zAccessTypezIuzK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool, bool);

unit zrvfi_read(uint64_t, sail_int, struct zMemoryOpResultzIz8bzCuz9zK);

void zmem_read(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIuzK, uint64_t, int64_t, bool, bool, bool);

void zmem_read_priv(struct zMemoryOpResultzIbzK *rop, struct zAccessTypezIuzK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool);

void zmem_read_priv_meta(struct zMemoryOpResultzIz8bzCuz9zK *rop, struct zAccessTypezIuzK, enum zPrivilege, uint64_t, int64_t, bool, bool, bool, bool);

void zmem_write_ea(struct zMemoryOpResultzIuzK *rop, uint64_t, int64_t, bool, bool, bool);

unit zrvfi_write(uint64_t, int64_t, lbits, unit, struct zMemoryOpResultzIozK);

void zphys_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, unit);

void zchecked_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, unit);

void zpmp_mem_write(struct zMemoryOpResultzIozK *rop, enum zwrite_kind, uint64_t, int64_t, lbits, struct zAccessTypezIuzK, enum zPrivilege, unit);

void zmem_write_value_priv_meta(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, struct zAccessTypezIuzK, enum zPrivilege, unit, bool, bool, bool);

void zmem_write_value_priv(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, enum zPrivilege, bool, bool, bool);

void zmem_write_value_meta(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, unit, unit, bool, bool, bool);

void zmem_write_value(struct zMemoryOpResultzIozK *rop, uint64_t, int64_t, lbits, bool, bool, bool);

void create_letbind_18(void);
void kill_letbind_18(void);


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

bool zisPTEPtr(uint64_t, uint64_t);

bool zisInvalidPTE(uint64_t, uint64_t);

void zto_pte_check(struct zPTE_Check *rop, bool);

void zcheckPTEPermission(struct zPTE_Check *rop, struct zAccessTypezIuzK, enum zPrivilege, bool, bool, struct zPTE_Bits, uint64_t, unit);

void zupdate_PTE_Bits(struct zoptionzIz8RPTE_BitszCbz9zK *rop, struct zPTE_Bits, struct zAccessTypezIuzK, uint64_t);

void zext_get_ptw_error(struct zPTW_Error *rop, unit);

void ztranslationException(struct zExceptionType *rop, struct zAccessTypezIuzK, struct zPTW_Error);

void create_letbind_19(void);
void kill_letbind_19(void);


uint64_t zcurAsid32(uint64_t);

uint64_t zcurPTB32(uint64_t);

void create_letbind_20(void);
void kill_letbind_20(void);


void create_letbind_21(void);
void kill_letbind_21(void);


void create_letbind_22(void);
void kill_letbind_22(void);


void create_letbind_23(void);
void kill_letbind_23(void);


struct zSV32_Vaddr zMk_SV32_Vaddr(uint64_t);

uint64_t z_get_SV32_Vaddr_PgOfs(struct zSV32_Vaddr);

uint64_t z_get_SV32_Vaddr_VPNi(struct zSV32_Vaddr);

struct zSV32_PTE zMk_SV32_PTE(uint64_t);

uint64_t z_get_SV32_PTE_BITS(struct zSV32_PTE);

struct zSV32_PTE z_update_SV32_PTE_BITS(struct zSV32_PTE, uint64_t);

uint64_t z_get_SV32_PTE_PPNi(struct zSV32_PTE);

void create_letbind_24(void);
void kill_letbind_24(void);


void create_letbind_25(void);
void kill_letbind_25(void);


void create_letbind_26(void);
void kill_letbind_26(void);


void create_letbind_27(void);
void kill_letbind_27(void);


void create_letbind_28(void);
void kill_letbind_28(void);


void create_letbind_29(void);
void kill_letbind_29(void);


void create_letbind_30(void);
void kill_letbind_30(void);


void create_letbind_31(void);
void kill_letbind_31(void);


void zmake_TLB_Entry(struct zTLB_Entry *rop, lbits, bool, lbits, lbits, lbits, sail_int, lbits, sail_int);

bool zmatch_TLB_Entry(struct zTLB_Entry, lbits, lbits);

bool zflush_TLB_Entry(struct zTLB_Entry, struct zoptionzIbzK, struct zoptionzIbzK);

uint64_t zto_phys_addr(uint64_t);

void zwalk32(struct zPTW_ResultzIbzCRSV32_PTEzK *rop, uint64_t, struct zAccessTypezIuzK, enum zPrivilege, bool, bool, uint64_t, sail_int, bool, unit);

void zlookup_TLB32(struct zoptionzIz8izCRTLB_Entryz9zK *rop, uint64_t, uint64_t);

unit zadd_to_TLB32(uint64_t, uint64_t, uint64_t, struct zSV32_PTE, uint64_t, sail_int, bool);

unit zwrite_TLB32(sail_int, struct zTLB_Entry);

unit zflush_TLB32(struct zoptionzIbzK, struct zoptionzIbzK);

void ztranslate32(struct zTR_ResultzIbzCUPTW_ErrorzK *rop, uint64_t, uint64_t, uint64_t, struct zAccessTypezIuzK, enum zPrivilege, bool, bool, sail_int, unit);

unit zinit_vmem_sv32(unit);

uint64_t zlegalizze_satp(enum zArchitecture, uint64_t, uint64_t);

enum zSATPMode ztranslationMode(enum zPrivilege);

void ztranslateAddr_priv(struct zTR_ResultzIbzCUExceptionTypezK *rop, uint64_t, struct zAccessTypezIuzK, enum zPrivilege);

void ztranslateAddr(struct zTR_ResultzIbzCUExceptionTypezK *rop, uint64_t, struct zAccessTypezIuzK);

unit zflush_TLB(struct zoptionzIbzK, struct zoptionzIbzK);

unit zinit_vmem(unit);

uint64_t zxt2(uint64_t);

uint64_t zgfmul(uint64_t, uint64_t);

uint64_t zaes_mixcolumn_byte_fwd(uint64_t);

uint64_t zaes_mixcolumn_byte_inv(uint64_t);

void create_letbind_32(void);
void kill_letbind_32(void);


void create_letbind_33(void);
void kill_letbind_33(void);


void create_letbind_34(void);
void kill_letbind_34(void);


uint64_t zsbox_lookup(uint64_t, zz5vecz8z5bv8z9);

uint64_t zaes_sbox_fwd(uint64_t);

uint64_t zaes_sbox_inv(uint64_t);

uint64_t zsm4_sbox(uint64_t);

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

bool zamo_width_valid(enum zword_width);

enum zRetired zprocess_loadres(uint64_t, uint64_t, struct zMemoryOpResultzIbzK, bool);

enum zamoop zencdec_amoop_backwards(uint64_t);

bool zencdec_amoop_backwards_matches(uint64_t);

enum zamoop zencdec_amoop_backwards_infallible(uint64_t);

void zamo_mnemonic_forwards(sail_string *rop, enum zamoop);

void zamo_mnemonic_forwards_infallible(sail_string *rop, enum zamoop);

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

void zcsr_mnemonic_forwards(sail_string *rop, enum zcsrop);

void zcsr_mnemonic_forwards_infallible(sail_string *rop, enum zcsrop);

uint64_t zencdec_rounding_mode_forwards(enum zrounding_mode);

enum zrounding_mode zencdec_rounding_mode_backwards(uint64_t);

bool zencdec_rounding_mode_backwards_matches(uint64_t);

uint64_t zencdec_rounding_mode_forwards_infallible(enum zrounding_mode);

enum zrounding_mode zencdec_rounding_mode_backwards_infallible(uint64_t);

void zfrm_mnemonic_forwards(sail_string *rop, enum zrounding_mode);

void zfrm_mnemonic_forwards_infallible(sail_string *rop, enum zrounding_mode);

bool zvalid_rounding_mode(uint64_t);

void zselect_instr_or_fcsr_rm(struct zoptionzIErounding_modez5zK *rop, enum zrounding_mode);

struct ztuple_z8z5bv1zCz0z5bv8zCz0z5bv23z9 zfsplit_S(uint64_t);

uint64_t zfmake_S(uint64_t, uint64_t, uint64_t);

bool zf_is_neg_inf_S(uint64_t);

bool zf_is_neg_norm_S(uint64_t);

bool zf_is_neg_subnorm_S(uint64_t);

bool zf_is_neg_zzero_S(uint64_t);

bool zf_is_pos_zzero_S(uint64_t);

bool zf_is_pos_subnorm_S(uint64_t);

bool zf_is_pos_norm_S(uint64_t);

bool zf_is_pos_inf_S(uint64_t);

bool zf_is_SNaN_S(uint64_t);

bool zf_is_QNaN_S(uint64_t);

bool zf_is_NaN_S(uint64_t);

uint64_t znegate_S(uint64_t);

struct ztuple_z8z5boolzCz0z5bv5z9 zfle_S(uint64_t, uint64_t, bool);

bool zhaveSingleFPU(unit);

enum zRetired zprocess_fload64(uint64_t, uint64_t, struct zMemoryOpResultzIbzK);

enum zRetired zprocess_fload32(uint64_t, uint64_t, struct zMemoryOpResultzIbzK);

enum zRetired zprocess_fload16(uint64_t, uint64_t, struct zMemoryOpResultzIbzK);

enum zRetired zprocess_fstore(uint64_t, struct zMemoryOpResultzIozK);

void zf_madd_type_mnemonic_S_forwards(sail_string *rop, enum zf_madd_op_S);

void zf_madd_type_mnemonic_S_forwards_infallible(sail_string *rop, enum zf_madd_op_S);

void zf_bin_rm_type_mnemonic_S_forwards(sail_string *rop, enum zf_bin_rm_op_S);

void zf_bin_rm_type_mnemonic_S_forwards_infallible(sail_string *rop, enum zf_bin_rm_op_S);

struct ztuple_z8z5bv1zCz0z5bv11zCz0z5bv52z9 zfsplit_D(uint64_t);

uint64_t zfmake_D(uint64_t, uint64_t, uint64_t);

bool zf_is_neg_inf_D(uint64_t);

bool zf_is_neg_norm_D(uint64_t);

bool zf_is_neg_subnorm_D(uint64_t);

bool zf_is_neg_zzero_D(uint64_t);

bool zf_is_pos_zzero_D(uint64_t);

bool zf_is_pos_subnorm_D(uint64_t);

bool zf_is_pos_norm_D(uint64_t);

bool zf_is_pos_inf_D(uint64_t);

bool zf_is_SNaN_D(uint64_t);

bool zf_is_QNaN_D(uint64_t);

bool zf_is_NaN_D(uint64_t);

uint64_t znegate_D(uint64_t);

struct ztuple_z8z5boolzCz0z5bv5z9 zfle_D(uint64_t, uint64_t, bool);

bool zhaveDoubleFPU(unit);

bool zvalidDoubleRegs(sail_int, zz5vecz8z5bv5z9);

void zf_madd_type_mnemonic_D_forwards(sail_string *rop, enum zf_madd_op_D);

void zf_madd_type_mnemonic_D_forwards_infallible(sail_string *rop, enum zf_madd_op_D);

void zf_bin_rm_type_mnemonic_D_forwards(sail_string *rop, enum zf_bin_rm_op_D);

void zf_bin_rm_type_mnemonic_D_forwards_infallible(sail_string *rop, enum zf_bin_rm_op_D);

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

struct ztuple_z8z5bv1zCz0z5bv5zCz0z5bv10z9 zfsplit_H(uint64_t);

uint64_t zfmake_H(uint64_t, uint64_t, uint64_t);

uint64_t znegate_H(uint64_t);

bool zf_is_neg_inf_H(uint64_t);

bool zf_is_neg_norm_H(uint64_t);

bool zf_is_neg_subnorm_H(uint64_t);

bool zf_is_pos_subnorm_H(uint64_t);

bool zf_is_pos_norm_H(uint64_t);

bool zf_is_pos_inf_H(uint64_t);

bool zf_is_neg_zzero_H(uint64_t);

bool zf_is_pos_zzero_H(uint64_t);

bool zf_is_SNaN_H(uint64_t);

bool zf_is_QNaN_H(uint64_t);

bool zf_is_NaN_H(uint64_t);

struct ztuple_z8z5boolzCz0z5bv5z9 zfle_H(uint64_t, uint64_t, bool);

bool zhaveHalfFPU(unit);

void zf_bin_rm_type_mnemonic_H_forwards(sail_string *rop, enum zf_bin_rm_op_H);

void zf_bin_rm_type_mnemonic_H_forwards_infallible(sail_string *rop, enum zf_bin_rm_op_H);

void zf_madd_type_mnemonic_H_forwards(sail_string *rop, enum zf_madd_op_H);

void zf_madd_type_mnemonic_H_forwards_infallible(sail_string *rop, enum zf_madd_op_H);

struct ztuple_z8z5bv5zCz0z5bv32z9 zfcvtmod_helper(uint64_t);

void zzzbkb_rtype_mnemonic_forwards(sail_string *rop, enum zbrop_zzbkb);

void zzzbkb_rtype_mnemonic_forwards_infallible(sail_string *rop, enum zbrop_zzbkb);

void zzzicond_mnemonic_forwards(sail_string *rop, enum zzzicondop);

void zzzicond_mnemonic_forwards_infallible(sail_string *rop, enum zzzicondop);

void zmaybe_vmask_backwards(sail_string *rop, uint64_t);

void zmaybe_vmask_backwards_infallible(sail_string *rop, uint64_t);

bool zvalid_eew_emul(sail_int, sail_int);

bool zvalid_vtype(unit);

bool zassert_vstart(sail_int);

bool zvalid_fp_op(int64_t, uint64_t);

bool zvalid_rd_mask(uint64_t, uint64_t);

bool zvalid_reg_overlap(uint64_t, uint64_t, sail_int, sail_int);

bool zvalid_segment(sail_int, sail_int);

bool zillegal_normal(uint64_t, uint64_t);

bool zillegal_vd_masked(uint64_t);

bool zillegal_vd_unmasked(unit);

bool zillegal_variable_width(uint64_t, uint64_t, sail_int, sail_int);

bool zillegal_reduction(unit);

bool zillegal_reduction_widen(sail_int, sail_int);

bool zillegal_fp_normal(uint64_t, uint64_t, int64_t, uint64_t);

bool zillegal_fp_vd_masked(uint64_t, int64_t, uint64_t);

bool zillegal_fp_vd_unmasked(int64_t, uint64_t);

bool zillegal_fp_variable_width(uint64_t, uint64_t, int64_t, uint64_t, sail_int, sail_int);

bool zillegal_fp_reduction(int64_t, uint64_t);

bool zillegal_fp_reduction_widen(int64_t, uint64_t, sail_int, sail_int);

bool zillegal_load(uint64_t, uint64_t, sail_int, sail_int, sail_int);

bool zillegal_store(sail_int, sail_int, sail_int);

bool zillegal_indexed_load(uint64_t, uint64_t, sail_int, sail_int, sail_int, sail_int);

bool zillegal_indexed_store(sail_int, sail_int, sail_int, sail_int);

void zget_scalar(lbits *rop, uint64_t, sail_int);

void zget_start_element(sail_int *rop, unit);

void zget_end_element(sail_int *rop, unit);

void zinit_masked_result(struct ztuple_z8z5vecz8z5bvz9zCz0z5vecz8z5boolz9z9 *rop, sail_int, sail_int, sail_int, zz5vecz8z5bvz9, zz5vecz8z5boolz9);

void zinit_masked_source(zz5vecz8z5boolz9 *rop, sail_int, sail_int, zz5vecz8z5boolz9);

void zinit_masked_result_carry(struct ztuple_z8z5vecz8z5boolz9zCz0z5vecz8z5boolz9z9 *rop, sail_int, sail_int, sail_int, zz5vecz8z5boolz9);

void zinit_masked_result_cmp(struct ztuple_z8z5vecz8z5boolz9zCz0z5vecz8z5boolz9z9 *rop, sail_int, sail_int, sail_int, zz5vecz8z5boolz9, zz5vecz8z5boolz9);

void zread_vreg_seg(zz5vecz8z5bvz9 *rop, sail_int, sail_int, sail_int, sail_int, uint64_t);

sbits zcanonical_NaN(int64_t);

bool zf_is_neg_inf(sbits);

bool zf_is_neg_norm(sbits);

bool zf_is_neg_subnorm(sbits);

bool zf_is_neg_zzero(sbits);

bool zf_is_pos_zzero(sbits);

bool zf_is_pos_subnorm(sbits);

bool zf_is_pos_norm(sbits);

bool zf_is_pos_inf(sbits);

bool zf_is_SNaN(sbits);

bool zf_is_QNaN(sbits);

bool zf_is_NaN(sbits);

sbits zget_scalar_fp(uint64_t, int64_t);

void zget_shift_amount(sail_int *rop, lbits, int64_t);

uint64_t zget_fixed_rounding_incr(lbits, sail_int);

void zunsigned_saturation(lbits *rop, sail_int, lbits);

void zsigned_saturation(lbits *rop, sail_int, lbits);

sbits znegate_fp(sbits);

sbits zfp_add(uint64_t, sbits, sbits);

sbits zfp_sub(uint64_t, sbits, sbits);

sbits zfp_min(sbits, sbits);

sbits zfp_max(sbits, sbits);

bool zfp_eq(sbits, sbits);

bool zfp_gt(sbits, sbits);

bool zfp_ge(sbits, sbits);

bool zfp_lt(sbits, sbits);

bool zfp_le(sbits, sbits);

sbits zfp_mul(uint64_t, sbits, sbits);

sbits zfp_div(uint64_t, sbits, sbits);

sbits zfp_muladd(uint64_t, sbits, sbits, sbits);

sbits zfp_nmuladd(uint64_t, sbits, sbits, sbits);

sbits zfp_mulsub(uint64_t, sbits, sbits, sbits);

sbits zfp_nmulsub(uint64_t, sbits, sbits, sbits);

sbits zfp_class(sbits);

sbits zfp_widen(sbits);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16ToI16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv8z9 zriscv_f16ToI8(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f32ToI16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16ToUi16(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv8z9 zriscv_f16ToUi8(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f32ToUi16(uint64_t, uint64_t);

void zcount_leadingzzeros(sail_int *rop, uint64_t, sail_int);

uint64_t zrsqrt7(sbits, bool);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Rsqrte7(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Rsqrte7(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Rsqrte7(uint64_t, uint64_t);

struct ztuple_z8z5boolzCz0z5bv64z9 zrecip7(sbits, uint64_t, bool);

struct ztuple_z8z5bv5zCz0z5bv16z9 zriscv_f16Recip7(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv32z9 zriscv_f32Recip7(uint64_t, uint64_t);

struct ztuple_z8z5bv5zCz0z5bv64z9 zriscv_f64Recip7(uint64_t, uint64_t);

void zsew_flag_backwards(sail_string *rop, uint64_t);

void zsew_flag_backwards_infallible(sail_string *rop, uint64_t);

void zmaybe_lmul_flag_backwards(sail_string *rop, uint64_t);

void zmaybe_lmul_flag_backwards_infallible(sail_string *rop, uint64_t);

void zmaybe_ta_flag_backwards(sail_string *rop, uint64_t);

void zmaybe_ta_flag_backwards_infallible(sail_string *rop, uint64_t);

void zmaybe_ma_flag_backwards(sail_string *rop, uint64_t);

void zmaybe_ma_flag_backwards_infallible(sail_string *rop, uint64_t);

enum zvsetop zencdec_vsetop_backwards(uint64_t);

bool zencdec_vsetop_backwards_matches(uint64_t);

enum zvsetop zencdec_vsetop_backwards_infallible(uint64_t);

void zvsettype_mnemonic_forwards(sail_string *rop, enum zvsetop);

void zvsettype_mnemonic_forwards_infallible(sail_string *rop, enum zvsetop);

enum zvvfunct6 zencdec_vvfunct6_backwards(uint64_t);

bool zencdec_vvfunct6_backwards_matches(uint64_t);

enum zvvfunct6 zencdec_vvfunct6_backwards_infallible(uint64_t);

void zvvtype_mnemonic_forwards(sail_string *rop, enum zvvfunct6);

void zvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zvvfunct6);

enum znvsfunct6 zencdec_nvsfunct6_backwards(uint64_t);

bool zencdec_nvsfunct6_backwards_matches(uint64_t);

enum znvsfunct6 zencdec_nvsfunct6_backwards_infallible(uint64_t);

void znvstype_mnemonic_forwards(sail_string *rop, enum znvsfunct6);

void znvstype_mnemonic_forwards_infallible(sail_string *rop, enum znvsfunct6);

enum znvfunct6 zencdec_nvfunct6_backwards(uint64_t);

bool zencdec_nvfunct6_backwards_matches(uint64_t);

enum znvfunct6 zencdec_nvfunct6_backwards_infallible(uint64_t);

void znvtype_mnemonic_forwards(sail_string *rop, enum znvfunct6);

void znvtype_mnemonic_forwards_infallible(sail_string *rop, enum znvfunct6);

enum zvxfunct6 zencdec_vxfunct6_backwards(uint64_t);

bool zencdec_vxfunct6_backwards_matches(uint64_t);

enum zvxfunct6 zencdec_vxfunct6_backwards_infallible(uint64_t);

void zvxtype_mnemonic_forwards(sail_string *rop, enum zvxfunct6);

void zvxtype_mnemonic_forwards_infallible(sail_string *rop, enum zvxfunct6);

enum znxsfunct6 zencdec_nxsfunct6_backwards(uint64_t);

bool zencdec_nxsfunct6_backwards_matches(uint64_t);

enum znxsfunct6 zencdec_nxsfunct6_backwards_infallible(uint64_t);

void znxstype_mnemonic_forwards(sail_string *rop, enum znxsfunct6);

void znxstype_mnemonic_forwards_infallible(sail_string *rop, enum znxsfunct6);

enum znxfunct6 zencdec_nxfunct6_backwards(uint64_t);

bool zencdec_nxfunct6_backwards_matches(uint64_t);

enum znxfunct6 zencdec_nxfunct6_backwards_infallible(uint64_t);

void znxtype_mnemonic_forwards(sail_string *rop, enum znxfunct6);

void znxtype_mnemonic_forwards_infallible(sail_string *rop, enum znxfunct6);

enum zvxsgfunct6 zencdec_vxsgfunct6_backwards(uint64_t);

bool zencdec_vxsgfunct6_backwards_matches(uint64_t);

enum zvxsgfunct6 zencdec_vxsgfunct6_backwards_infallible(uint64_t);

void zvxsg_mnemonic_forwards(sail_string *rop, enum zvxsgfunct6);

void zvxsg_mnemonic_forwards_infallible(sail_string *rop, enum zvxsgfunct6);

enum zvifunct6 zencdec_vifunct6_backwards(uint64_t);

bool zencdec_vifunct6_backwards_matches(uint64_t);

enum zvifunct6 zencdec_vifunct6_backwards_infallible(uint64_t);

void zvitype_mnemonic_forwards(sail_string *rop, enum zvifunct6);

void zvitype_mnemonic_forwards_infallible(sail_string *rop, enum zvifunct6);

enum znisfunct6 zencdec_nisfunct6_backwards(uint64_t);

bool zencdec_nisfunct6_backwards_matches(uint64_t);

enum znisfunct6 zencdec_nisfunct6_backwards_infallible(uint64_t);

void znistype_mnemonic_forwards(sail_string *rop, enum znisfunct6);

void znistype_mnemonic_forwards_infallible(sail_string *rop, enum znisfunct6);

enum znifunct6 zencdec_nifunct6_backwards(uint64_t);

bool zencdec_nifunct6_backwards_matches(uint64_t);

enum znifunct6 zencdec_nifunct6_backwards_infallible(uint64_t);

void znitype_mnemonic_forwards(sail_string *rop, enum znifunct6);

void znitype_mnemonic_forwards_infallible(sail_string *rop, enum znifunct6);

enum zvisgfunct6 zencdec_visgfunct6_backwards(uint64_t);

bool zencdec_visgfunct6_backwards_matches(uint64_t);

enum zvisgfunct6 zencdec_visgfunct6_backwards_infallible(uint64_t);

void zvisg_mnemonic_forwards(sail_string *rop, enum zvisgfunct6);

void zvisg_mnemonic_forwards_infallible(sail_string *rop, enum zvisgfunct6);

void zsimm_string_forwards(sail_string *rop, uint64_t);

void zsimm_string_forwards_infallible(sail_string *rop, uint64_t);

enum zmvvfunct6 zencdec_mvvfunct6_backwards(uint64_t);

bool zencdec_mvvfunct6_backwards_matches(uint64_t);

enum zmvvfunct6 zencdec_mvvfunct6_backwards_infallible(uint64_t);

void zmvvtype_mnemonic_forwards(sail_string *rop, enum zmvvfunct6);

void zmvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zmvvfunct6);

enum zmvvmafunct6 zencdec_mvvmafunct6_backwards(uint64_t);

bool zencdec_mvvmafunct6_backwards_matches(uint64_t);

enum zmvvmafunct6 zencdec_mvvmafunct6_backwards_infallible(uint64_t);

void zmvvmatype_mnemonic_forwards(sail_string *rop, enum zmvvmafunct6);

void zmvvmatype_mnemonic_forwards_infallible(sail_string *rop, enum zmvvmafunct6);

enum zwvvfunct6 zencdec_wvvfunct6_backwards(uint64_t);

bool zencdec_wvvfunct6_backwards_matches(uint64_t);

enum zwvvfunct6 zencdec_wvvfunct6_backwards_infallible(uint64_t);

void zwvvtype_mnemonic_forwards(sail_string *rop, enum zwvvfunct6);

void zwvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zwvvfunct6);

enum zwvfunct6 zencdec_wvfunct6_backwards(uint64_t);

bool zencdec_wvfunct6_backwards_matches(uint64_t);

enum zwvfunct6 zencdec_wvfunct6_backwards_infallible(uint64_t);

void zwvtype_mnemonic_forwards(sail_string *rop, enum zwvfunct6);

void zwvtype_mnemonic_forwards_infallible(sail_string *rop, enum zwvfunct6);

enum zwmvvfunct6 zencdec_wmvvfunct6_backwards(uint64_t);

bool zencdec_wmvvfunct6_backwards_matches(uint64_t);

enum zwmvvfunct6 zencdec_wmvvfunct6_backwards_infallible(uint64_t);

void zwmvvtype_mnemonic_forwards(sail_string *rop, enum zwmvvfunct6);

void zwmvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zwmvvfunct6);

enum zvext2funct6 zvext2_vs1_backwards(uint64_t);

bool zvext2_vs1_backwards_matches(uint64_t);

enum zvext2funct6 zvext2_vs1_backwards_infallible(uint64_t);

void zvext2type_mnemonic_forwards(sail_string *rop, enum zvext2funct6);

void zvext2type_mnemonic_forwards_infallible(sail_string *rop, enum zvext2funct6);

enum zvext4funct6 zvext4_vs1_backwards(uint64_t);

bool zvext4_vs1_backwards_matches(uint64_t);

enum zvext4funct6 zvext4_vs1_backwards_infallible(uint64_t);

void zvext4type_mnemonic_forwards(sail_string *rop, enum zvext4funct6);

void zvext4type_mnemonic_forwards_infallible(sail_string *rop, enum zvext4funct6);

enum zvext8funct6 zvext8_vs1_backwards(uint64_t);

bool zvext8_vs1_backwards_matches(uint64_t);

enum zvext8funct6 zvext8_vs1_backwards_infallible(uint64_t);

void zvext8type_mnemonic_forwards(sail_string *rop, enum zvext8funct6);

void zvext8type_mnemonic_forwards_infallible(sail_string *rop, enum zvext8funct6);

enum zmvxfunct6 zencdec_mvxfunct6_backwards(uint64_t);

bool zencdec_mvxfunct6_backwards_matches(uint64_t);

enum zmvxfunct6 zencdec_mvxfunct6_backwards_infallible(uint64_t);

void zmvxtype_mnemonic_forwards(sail_string *rop, enum zmvxfunct6);

void zmvxtype_mnemonic_forwards_infallible(sail_string *rop, enum zmvxfunct6);

enum zmvxmafunct6 zencdec_mvxmafunct6_backwards(uint64_t);

bool zencdec_mvxmafunct6_backwards_matches(uint64_t);

enum zmvxmafunct6 zencdec_mvxmafunct6_backwards_infallible(uint64_t);

void zmvxmatype_mnemonic_forwards(sail_string *rop, enum zmvxmafunct6);

void zmvxmatype_mnemonic_forwards_infallible(sail_string *rop, enum zmvxmafunct6);

enum zwvxfunct6 zencdec_wvxfunct6_backwards(uint64_t);

bool zencdec_wvxfunct6_backwards_matches(uint64_t);

enum zwvxfunct6 zencdec_wvxfunct6_backwards_infallible(uint64_t);

void zwvxtype_mnemonic_forwards(sail_string *rop, enum zwvxfunct6);

void zwvxtype_mnemonic_forwards_infallible(sail_string *rop, enum zwvxfunct6);

enum zwxfunct6 zencdec_wxfunct6_backwards(uint64_t);

bool zencdec_wxfunct6_backwards_matches(uint64_t);

enum zwxfunct6 zencdec_wxfunct6_backwards_infallible(uint64_t);

void zwxtype_mnemonic_forwards(sail_string *rop, enum zwxfunct6);

void zwxtype_mnemonic_forwards_infallible(sail_string *rop, enum zwxfunct6);

enum zwmvxfunct6 zencdec_wmvxfunct6_backwards(uint64_t);

bool zencdec_wmvxfunct6_backwards_matches(uint64_t);

enum zwmvxfunct6 zencdec_wmvxfunct6_backwards_infallible(uint64_t);

void zwmvxtype_mnemonic_forwards(sail_string *rop, enum zwmvxfunct6);

void zwmvxtype_mnemonic_forwards_infallible(sail_string *rop, enum zwmvxfunct6);

enum zfvvfunct6 zencdec_fvvfunct6_backwards(uint64_t);

bool zencdec_fvvfunct6_backwards_matches(uint64_t);

enum zfvvfunct6 zencdec_fvvfunct6_backwards_infallible(uint64_t);

void zfvvtype_mnemonic_forwards(sail_string *rop, enum zfvvfunct6);

void zfvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zfvvfunct6);

enum zfvvmafunct6 zencdec_fvvmafunct6_backwards(uint64_t);

bool zencdec_fvvmafunct6_backwards_matches(uint64_t);

enum zfvvmafunct6 zencdec_fvvmafunct6_backwards_infallible(uint64_t);

void zfvvmatype_mnemonic_forwards(sail_string *rop, enum zfvvmafunct6);

void zfvvmatype_mnemonic_forwards_infallible(sail_string *rop, enum zfvvmafunct6);

enum zfwvvfunct6 zencdec_fwvvfunct6_backwards(uint64_t);

bool zencdec_fwvvfunct6_backwards_matches(uint64_t);

enum zfwvvfunct6 zencdec_fwvvfunct6_backwards_infallible(uint64_t);

void zfwvvtype_mnemonic_forwards(sail_string *rop, enum zfwvvfunct6);

void zfwvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zfwvvfunct6);

enum zfwvvmafunct6 zencdec_fwvvmafunct6_backwards(uint64_t);

bool zencdec_fwvvmafunct6_backwards_matches(uint64_t);

enum zfwvvmafunct6 zencdec_fwvvmafunct6_backwards_infallible(uint64_t);

void zfwvvmatype_mnemonic_forwards(sail_string *rop, enum zfwvvmafunct6);

void zfwvvmatype_mnemonic_forwards_infallible(sail_string *rop, enum zfwvvmafunct6);

enum zfwvfunct6 zencdec_fwvfunct6_backwards(uint64_t);

bool zencdec_fwvfunct6_backwards_matches(uint64_t);

enum zfwvfunct6 zencdec_fwvfunct6_backwards_infallible(uint64_t);

void zfwvtype_mnemonic_forwards(sail_string *rop, enum zfwvfunct6);

void zfwvtype_mnemonic_forwards_infallible(sail_string *rop, enum zfwvfunct6);

enum zvfunary0 zencdec_vfunary0_vs1_backwards(uint64_t);

bool zencdec_vfunary0_vs1_backwards_matches(uint64_t);

enum zvfunary0 zencdec_vfunary0_vs1_backwards_infallible(uint64_t);

void zvfunary0_mnemonic_forwards(sail_string *rop, enum zvfunary0);

void zvfunary0_mnemonic_forwards_infallible(sail_string *rop, enum zvfunary0);

enum zvfwunary0 zencdec_vfwunary0_vs1_backwards(uint64_t);

bool zencdec_vfwunary0_vs1_backwards_matches(uint64_t);

enum zvfwunary0 zencdec_vfwunary0_vs1_backwards_infallible(uint64_t);

void zvfwunary0_mnemonic_forwards(sail_string *rop, enum zvfwunary0);

void zvfwunary0_mnemonic_forwards_infallible(sail_string *rop, enum zvfwunary0);

enum zvfnunary0 zencdec_vfnunary0_vs1_backwards(uint64_t);

bool zencdec_vfnunary0_vs1_backwards_matches(uint64_t);

enum zvfnunary0 zencdec_vfnunary0_vs1_backwards_infallible(uint64_t);

void zvfnunary0_mnemonic_forwards(sail_string *rop, enum zvfnunary0);

void zvfnunary0_mnemonic_forwards_infallible(sail_string *rop, enum zvfnunary0);

enum zvfunary1 zencdec_vfunary1_vs1_backwards(uint64_t);

bool zencdec_vfunary1_vs1_backwards_matches(uint64_t);

enum zvfunary1 zencdec_vfunary1_vs1_backwards_infallible(uint64_t);

void zvfunary1_mnemonic_forwards(sail_string *rop, enum zvfunary1);

void zvfunary1_mnemonic_forwards_infallible(sail_string *rop, enum zvfunary1);

enum zfvffunct6 zencdec_fvffunct6_backwards(uint64_t);

bool zencdec_fvffunct6_backwards_matches(uint64_t);

enum zfvffunct6 zencdec_fvffunct6_backwards_infallible(uint64_t);

void zfvftype_mnemonic_forwards(sail_string *rop, enum zfvffunct6);

void zfvftype_mnemonic_forwards_infallible(sail_string *rop, enum zfvffunct6);

enum zfvfmafunct6 zencdec_fvfmafunct6_backwards(uint64_t);

bool zencdec_fvfmafunct6_backwards_matches(uint64_t);

enum zfvfmafunct6 zencdec_fvfmafunct6_backwards_infallible(uint64_t);

void zfvfmatype_mnemonic_forwards(sail_string *rop, enum zfvfmafunct6);

void zfvfmatype_mnemonic_forwards_infallible(sail_string *rop, enum zfvfmafunct6);

enum zfwvffunct6 zencdec_fwvffunct6_backwards(uint64_t);

bool zencdec_fwvffunct6_backwards_matches(uint64_t);

enum zfwvffunct6 zencdec_fwvffunct6_backwards_infallible(uint64_t);

void zfwvftype_mnemonic_forwards(sail_string *rop, enum zfwvffunct6);

void zfwvftype_mnemonic_forwards_infallible(sail_string *rop, enum zfwvffunct6);

enum zfwvfmafunct6 zencdec_fwvfmafunct6_backwards(uint64_t);

bool zencdec_fwvfmafunct6_backwards_matches(uint64_t);

enum zfwvfmafunct6 zencdec_fwvfmafunct6_backwards_infallible(uint64_t);

void zfwvfmatype_mnemonic_forwards(sail_string *rop, enum zfwvfmafunct6);

void zfwvfmatype_mnemonic_forwards_infallible(sail_string *rop, enum zfwvfmafunct6);

enum zfwffunct6 zencdec_fwffunct6_backwards(uint64_t);

bool zencdec_fwffunct6_backwards_matches(uint64_t);

enum zfwffunct6 zencdec_fwffunct6_backwards_infallible(uint64_t);

void zfwftype_mnemonic_forwards(sail_string *rop, enum zfwffunct6);

void zfwftype_mnemonic_forwards_infallible(sail_string *rop, enum zfwffunct6);

int64_t znfields_int_forwards(uint64_t);

int64_t znfields_int_forwards_infallible(uint64_t);

void znfields_string_forwards(sail_string *rop, uint64_t);

void znfields_string_forwards_infallible(sail_string *rop, uint64_t);

void zvlewidth_bitsnumberstr_forwards(sail_string *rop, enum zvlewidth);

void zvlewidth_bitsnumberstr_forwards_infallible(sail_string *rop, enum zvlewidth);

enum zvlewidth zencdec_vlewidth_backwards(uint64_t);

bool zencdec_vlewidth_backwards_matches(uint64_t);

enum zvlewidth zencdec_vlewidth_backwards_infallible(uint64_t);

int64_t zvlewidth_bytesnumber_forwards(enum zvlewidth);

int64_t zvlewidth_bytesnumber_forwards_infallible(enum zvlewidth);

int64_t zvlewidth_pow_forwards(enum zvlewidth);

int64_t zvlewidth_pow_forwards_infallible(enum zvlewidth);

enum zword_width zbytes_wordwidth_forwards(int64_t);

enum zword_width zbytes_wordwidth_forwards_infallible(int64_t);

enum zRetired zprocess_vlseg(int64_t, uint64_t, uint64_t, int64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vlsegff(int64_t, uint64_t, uint64_t, int64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vsseg(int64_t, uint64_t, uint64_t, int64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vlsseg(int64_t, uint64_t, uint64_t, int64_t, uint64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vssseg(int64_t, uint64_t, uint64_t, int64_t, uint64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vlxseg(int64_t, uint64_t, uint64_t, int64_t, int64_t, sail_int, sail_int, uint64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vsxseg(int64_t, uint64_t, uint64_t, int64_t, int64_t, sail_int, sail_int, uint64_t, uint64_t, sail_int, sail_int);

enum zRetired zprocess_vlre(int64_t, uint64_t, int64_t, uint64_t, sail_int);

enum zRetired zprocess_vsre(int64_t, int64_t, uint64_t, uint64_t, sail_int);

enum zvmlsop zencdec_lsop_backwards(uint64_t);

bool zencdec_lsop_backwards_matches(uint64_t);

enum zvmlsop zencdec_lsop_backwards_infallible(uint64_t);

enum zRetired zprocess_vm(uint64_t, uint64_t, sail_int, sail_int, enum zvmlsop);

void zvmtype_mnemonic_forwards(sail_string *rop, enum zvmlsop);

void zvmtype_mnemonic_forwards_infallible(sail_string *rop, enum zvmlsop);

enum zmmfunct6 zencdec_mmfunct6_backwards(uint64_t);

bool zencdec_mmfunct6_backwards_matches(uint64_t);

enum zmmfunct6 zencdec_mmfunct6_backwards_infallible(uint64_t);

void zmmtype_mnemonic_forwards(sail_string *rop, enum zmmfunct6);

void zmmtype_mnemonic_forwards_infallible(sail_string *rop, enum zmmfunct6);

enum zvvmfunct6 zencdec_vvmfunct6_backwards(uint64_t);

bool zencdec_vvmfunct6_backwards_matches(uint64_t);

enum zvvmfunct6 zencdec_vvmfunct6_backwards_infallible(uint64_t);

void zvvmtype_mnemonic_forwards(sail_string *rop, enum zvvmfunct6);

void zvvmtype_mnemonic_forwards_infallible(sail_string *rop, enum zvvmfunct6);

enum zvvmcfunct6 zencdec_vvmcfunct6_backwards(uint64_t);

bool zencdec_vvmcfunct6_backwards_matches(uint64_t);

enum zvvmcfunct6 zencdec_vvmcfunct6_backwards_infallible(uint64_t);

void zvvmctype_mnemonic_forwards(sail_string *rop, enum zvvmcfunct6);

void zvvmctype_mnemonic_forwards_infallible(sail_string *rop, enum zvvmcfunct6);

enum zvvmsfunct6 zencdec_vvmsfunct6_backwards(uint64_t);

bool zencdec_vvmsfunct6_backwards_matches(uint64_t);

enum zvvmsfunct6 zencdec_vvmsfunct6_backwards_infallible(uint64_t);

void zvvmstype_mnemonic_forwards(sail_string *rop, enum zvvmsfunct6);

void zvvmstype_mnemonic_forwards_infallible(sail_string *rop, enum zvvmsfunct6);

enum zvvcmpfunct6 zencdec_vvcmpfunct6_backwards(uint64_t);

bool zencdec_vvcmpfunct6_backwards_matches(uint64_t);

enum zvvcmpfunct6 zencdec_vvcmpfunct6_backwards_infallible(uint64_t);

void zvvcmptype_mnemonic_forwards(sail_string *rop, enum zvvcmpfunct6);

void zvvcmptype_mnemonic_forwards_infallible(sail_string *rop, enum zvvcmpfunct6);

enum zvxmfunct6 zencdec_vxmfunct6_backwards(uint64_t);

bool zencdec_vxmfunct6_backwards_matches(uint64_t);

enum zvxmfunct6 zencdec_vxmfunct6_backwards_infallible(uint64_t);

void zvxmtype_mnemonic_forwards(sail_string *rop, enum zvxmfunct6);

void zvxmtype_mnemonic_forwards_infallible(sail_string *rop, enum zvxmfunct6);

enum zvxmcfunct6 zencdec_vxmcfunct6_backwards(uint64_t);

bool zencdec_vxmcfunct6_backwards_matches(uint64_t);

enum zvxmcfunct6 zencdec_vxmcfunct6_backwards_infallible(uint64_t);

void zvxmctype_mnemonic_forwards(sail_string *rop, enum zvxmcfunct6);

void zvxmctype_mnemonic_forwards_infallible(sail_string *rop, enum zvxmcfunct6);

enum zvxmsfunct6 zencdec_vxmsfunct6_backwards(uint64_t);

bool zencdec_vxmsfunct6_backwards_matches(uint64_t);

enum zvxmsfunct6 zencdec_vxmsfunct6_backwards_infallible(uint64_t);

void zvxmstype_mnemonic_forwards(sail_string *rop, enum zvxmsfunct6);

void zvxmstype_mnemonic_forwards_infallible(sail_string *rop, enum zvxmsfunct6);

enum zvxcmpfunct6 zencdec_vxcmpfunct6_backwards(uint64_t);

bool zencdec_vxcmpfunct6_backwards_matches(uint64_t);

enum zvxcmpfunct6 zencdec_vxcmpfunct6_backwards_infallible(uint64_t);

void zvxcmptype_mnemonic_forwards(sail_string *rop, enum zvxcmpfunct6);

void zvxcmptype_mnemonic_forwards_infallible(sail_string *rop, enum zvxcmpfunct6);

enum zvimfunct6 zencdec_vimfunct6_backwards(uint64_t);

bool zencdec_vimfunct6_backwards_matches(uint64_t);

enum zvimfunct6 zencdec_vimfunct6_backwards_infallible(uint64_t);

void zvimtype_mnemonic_forwards(sail_string *rop, enum zvimfunct6);

void zvimtype_mnemonic_forwards_infallible(sail_string *rop, enum zvimfunct6);

enum zvimcfunct6 zencdec_vimcfunct6_backwards(uint64_t);

bool zencdec_vimcfunct6_backwards_matches(uint64_t);

enum zvimcfunct6 zencdec_vimcfunct6_backwards_infallible(uint64_t);

void zvimctype_mnemonic_forwards(sail_string *rop, enum zvimcfunct6);

void zvimctype_mnemonic_forwards_infallible(sail_string *rop, enum zvimcfunct6);

enum zvimsfunct6 zencdec_vimsfunct6_backwards(uint64_t);

bool zencdec_vimsfunct6_backwards_matches(uint64_t);

enum zvimsfunct6 zencdec_vimsfunct6_backwards_infallible(uint64_t);

void zvimstype_mnemonic_forwards(sail_string *rop, enum zvimsfunct6);

void zvimstype_mnemonic_forwards_infallible(sail_string *rop, enum zvimsfunct6);

enum zvicmpfunct6 zencdec_vicmpfunct6_backwards(uint64_t);

bool zencdec_vicmpfunct6_backwards_matches(uint64_t);

enum zvicmpfunct6 zencdec_vicmpfunct6_backwards_infallible(uint64_t);

void zvicmptype_mnemonic_forwards(sail_string *rop, enum zvicmpfunct6);

void zvicmptype_mnemonic_forwards_infallible(sail_string *rop, enum zvicmpfunct6);

enum zfvvmfunct6 zencdec_fvvmfunct6_backwards(uint64_t);

bool zencdec_fvvmfunct6_backwards_matches(uint64_t);

enum zfvvmfunct6 zencdec_fvvmfunct6_backwards_infallible(uint64_t);

void zfvvmtype_mnemonic_forwards(sail_string *rop, enum zfvvmfunct6);

void zfvvmtype_mnemonic_forwards_infallible(sail_string *rop, enum zfvvmfunct6);

enum zfvfmfunct6 zencdec_fvfmfunct6_backwards(uint64_t);

bool zencdec_fvfmfunct6_backwards_matches(uint64_t);

enum zfvfmfunct6 zencdec_fvfmfunct6_backwards_infallible(uint64_t);

void zfvfmtype_mnemonic_forwards(sail_string *rop, enum zfvfmfunct6);

void zfvfmtype_mnemonic_forwards_infallible(sail_string *rop, enum zfvfmfunct6);

enum zrivvfunct6 zencdec_rivvfunct6_backwards(uint64_t);

bool zencdec_rivvfunct6_backwards_matches(uint64_t);

enum zrivvfunct6 zencdec_rivvfunct6_backwards_infallible(uint64_t);

void zrivvtype_mnemonic_forwards(sail_string *rop, enum zrivvfunct6);

void zrivvtype_mnemonic_forwards_infallible(sail_string *rop, enum zrivvfunct6);

enum zrmvvfunct6 zencdec_rmvvfunct6_backwards(uint64_t);

bool zencdec_rmvvfunct6_backwards_matches(uint64_t);

enum zrmvvfunct6 zencdec_rmvvfunct6_backwards_infallible(uint64_t);

void zrmvvtype_mnemonic_forwards(sail_string *rop, enum zrmvvfunct6);

void zrmvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zrmvvfunct6);

enum zrfvvfunct6 zencdec_rfvvfunct6_backwards(uint64_t);

bool zencdec_rfvvfunct6_backwards_matches(uint64_t);

enum zrfvvfunct6 zencdec_rfvvfunct6_backwards_infallible(uint64_t);

enum zRetired zprocess_rfvv_single(enum zrfvvfunct6, uint64_t, uint64_t, uint64_t, uint64_t, sail_int, int64_t, sail_int);

enum zRetired zprocess_rfvv_widen(enum zrfvvfunct6, uint64_t, uint64_t, uint64_t, uint64_t, sail_int, int64_t, sail_int);

void zrfvvtype_mnemonic_forwards(sail_string *rop, enum zrfvvfunct6);

void zrfvvtype_mnemonic_forwards_infallible(sail_string *rop, enum zrfvvfunct6);

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

// register zPC
extern uint64_t zPC;

// register znextPC
extern uint64_t znextPC;

// register zinstbits
extern uint64_t zinstbits;

// register zx1
extern uint64_t zx1;

// register zx2
extern uint64_t zx2;

// register zx3
extern uint64_t zx3;

// register zx4
extern uint64_t zx4;

// register zx5
extern uint64_t zx5;

// register zx6
extern uint64_t zx6;

// register zx7
extern uint64_t zx7;

// register zx8
extern uint64_t zx8;

// register zx9
extern uint64_t zx9;

// register zx10
extern uint64_t zx10;

// register zx11
extern uint64_t zx11;

// register zx12
extern uint64_t zx12;

// register zx13
extern uint64_t zx13;

// register zx14
extern uint64_t zx14;

// register zx15
extern uint64_t zx15;

// register zx16
extern uint64_t zx16;

// register zx17
extern uint64_t zx17;

// register zx18
extern uint64_t zx18;

// register zx19
extern uint64_t zx19;

// register zx20
extern uint64_t zx20;

// register zx21
extern uint64_t zx21;

// register zx22
extern uint64_t zx22;

// register zx23
extern uint64_t zx23;

// register zx24
extern uint64_t zx24;

// register zx25
extern uint64_t zx25;

// register zx26
extern uint64_t zx26;

// register zx27
extern uint64_t zx27;

// register zx28
extern uint64_t zx28;

// register zx29
extern uint64_t zx29;

// register zx30
extern uint64_t zx30;

// register zx31
extern uint64_t zx31;

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
extern struct zMEnvcfg zmenvcfg;

// register zsenvcfg
extern struct zSEnvcfg zsenvcfg;

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

// register zfloat_result
extern uint64_t zfloat_result;

// register zfloat_fflags
extern uint64_t zfloat_fflags;

// register zf0
extern uint64_t zf0;

// register zf1
extern uint64_t zf1;

// register zf2
extern uint64_t zf2;

// register zf3
extern uint64_t zf3;

// register zf4
extern uint64_t zf4;

// register zf5
extern uint64_t zf5;

// register zf6
extern uint64_t zf6;

// register zf7
extern uint64_t zf7;

// register zf8
extern uint64_t zf8;

// register zf9
extern uint64_t zf9;

// register zf10
extern uint64_t zf10;

// register zf11
extern uint64_t zf11;

// register zf12
extern uint64_t zf12;

// register zf13
extern uint64_t zf13;

// register zf14
extern uint64_t zf14;

// register zf15
extern uint64_t zf15;

// register zf16
extern uint64_t zf16;

// register zf17
extern uint64_t zf17;

// register zf18
extern uint64_t zf18;

// register zf19
extern uint64_t zf19;

// register zf20
extern uint64_t zf20;

// register zf21
extern uint64_t zf21;

// register zf22
extern uint64_t zf22;

// register zf23
extern uint64_t zf23;

// register zf24
extern uint64_t zf24;

// register zf25
extern uint64_t zf25;

// register zf26
extern uint64_t zf26;

// register zf27
extern uint64_t zf27;

// register zf28
extern uint64_t zf28;

// register zf29
extern uint64_t zf29;

// register zf30
extern uint64_t zf30;

// register zf31
extern uint64_t zf31;

// register zfcsr
extern struct zFcsr zfcsr;

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

// register ztlb32
extern struct zoptionzIRTLB_EntryzK ztlb32;

// register zsatp
extern uint64_t zsatp;



#ifdef __cplusplus
}
#endif
