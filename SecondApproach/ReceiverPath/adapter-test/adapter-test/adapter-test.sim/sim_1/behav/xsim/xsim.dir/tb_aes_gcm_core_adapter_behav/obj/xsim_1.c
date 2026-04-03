/**********************************************************************/
/*   ____  ____                                                       */
/*  /   /\/   /                                                       */
/* /___/  \  /                                                        */
/* \   \   \/                                                         */
/*  \   \        Copyright (c) 2003-2020 Xilinx, Inc.                 */
/*  /   /        All Right Reserved.                                  */
/* /---/   /\                                                         */
/* \   \  /  \                                                        */
/*  \___\/\___\                                                       */
/**********************************************************************/

#if defined(_WIN32)
 #include "stdio.h"
 #define IKI_DLLESPEC __declspec(dllimport)
#else
 #define IKI_DLLESPEC
#endif
#include "iki.h"
#include <string.h>
#include <math.h>
#ifdef __GNUC__
#include <stdlib.h>
#else
#include <malloc.h>
#define alloca _alloca
#endif
/**********************************************************************/
/*   ____  ____                                                       */
/*  /   /\/   /                                                       */
/* /___/  \  /                                                        */
/* \   \   \/                                                         */
/*  \   \        Copyright (c) 2003-2020 Xilinx, Inc.                 */
/*  /   /        All Right Reserved.                                  */
/* /---/   /\                                                         */
/* \   \  /  \                                                        */
/*  \___\/\___\                                                       */
/**********************************************************************/

#if defined(_WIN32)
 #include "stdio.h"
 #define IKI_DLLESPEC __declspec(dllimport)
#else
 #define IKI_DLLESPEC
#endif
#include "iki.h"
#include <string.h>
#include <math.h>
#ifdef __GNUC__
#include <stdlib.h>
#else
#include <malloc.h>
#define alloca _alloca
#endif
typedef void (*funcp)(char *, char *);
extern int main(int, char**);
IKI_DLLESPEC extern void execute_2(char*, char *);
IKI_DLLESPEC extern void execute_1224(char*, char *);
IKI_DLLESPEC extern void execute_1233(char*, char *);
IKI_DLLESPEC extern void execute_1978(char*, char *);
IKI_DLLESPEC extern void execute_1979(char*, char *);
IKI_DLLESPEC extern void execute_1980(char*, char *);
IKI_DLLESPEC extern void execute_1981(char*, char *);
IKI_DLLESPEC extern void execute_1982(char*, char *);
IKI_DLLESPEC extern void execute_1983(char*, char *);
IKI_DLLESPEC extern void execute_1984(char*, char *);
IKI_DLLESPEC extern void execute_1985(char*, char *);
IKI_DLLESPEC extern void execute_1986(char*, char *);
IKI_DLLESPEC extern void execute_1987(char*, char *);
IKI_DLLESPEC extern void execute_1988(char*, char *);
IKI_DLLESPEC extern void execute_1989(char*, char *);
IKI_DLLESPEC extern void execute_1990(char*, char *);
IKI_DLLESPEC extern void execute_1991(char*, char *);
IKI_DLLESPEC extern void execute_1992(char*, char *);
IKI_DLLESPEC extern void execute_1993(char*, char *);
IKI_DLLESPEC extern void execute_1223(char*, char *);
IKI_DLLESPEC extern void execute_1239(char*, char *);
IKI_DLLESPEC extern void execute_1958(char*, char *);
IKI_DLLESPEC extern void vlog_const_rhs_process_execute_0_fast_for_reg(char*, char*, char*);
IKI_DLLESPEC extern void execute_1960(char*, char *);
IKI_DLLESPEC extern void execute_1961(char*, char *);
IKI_DLLESPEC extern void execute_1962(char*, char *);
IKI_DLLESPEC extern void execute_1963(char*, char *);
IKI_DLLESPEC extern void execute_1964(char*, char *);
IKI_DLLESPEC extern void execute_1965(char*, char *);
IKI_DLLESPEC extern void execute_1966(char*, char *);
IKI_DLLESPEC extern void execute_1967(char*, char *);
IKI_DLLESPEC extern void execute_1968(char*, char *);
IKI_DLLESPEC extern void execute_1969(char*, char *);
IKI_DLLESPEC extern void execute_1970(char*, char *);
IKI_DLLESPEC extern void execute_1971(char*, char *);
IKI_DLLESPEC extern void execute_1972(char*, char *);
IKI_DLLESPEC extern void execute_1973(char*, char *);
IKI_DLLESPEC extern void execute_1974(char*, char *);
IKI_DLLESPEC extern void execute_1975(char*, char *);
IKI_DLLESPEC extern void execute_1976(char*, char *);
IKI_DLLESPEC extern void execute_1977(char*, char *);
IKI_DLLESPEC extern void execute_8(char*, char *);
IKI_DLLESPEC extern void execute_1240(char*, char *);
IKI_DLLESPEC extern void execute_1241(char*, char *);
IKI_DLLESPEC extern void execute_1949(char*, char *);
IKI_DLLESPEC extern void execute_1950(char*, char *);
IKI_DLLESPEC extern void execute_1951(char*, char *);
IKI_DLLESPEC extern void execute_1952(char*, char *);
IKI_DLLESPEC extern void execute_1953(char*, char *);
IKI_DLLESPEC extern void execute_1954(char*, char *);
IKI_DLLESPEC extern void execute_1955(char*, char *);
IKI_DLLESPEC extern void execute_1956(char*, char *);
IKI_DLLESPEC extern void execute_1957(char*, char *);
IKI_DLLESPEC extern void execute_1216(char*, char *);
IKI_DLLESPEC extern void execute_1217(char*, char *);
IKI_DLLESPEC extern void execute_1218(char*, char *);
IKI_DLLESPEC extern void execute_1242(char*, char *);
IKI_DLLESPEC extern void execute_1938(char*, char *);
IKI_DLLESPEC extern void execute_1939(char*, char *);
IKI_DLLESPEC extern void execute_1940(char*, char *);
IKI_DLLESPEC extern void execute_1941(char*, char *);
IKI_DLLESPEC extern void execute_1803(char*, char *);
IKI_DLLESPEC extern void execute_1804(char*, char *);
IKI_DLLESPEC extern void execute_1268(char*, char *);
IKI_DLLESPEC extern void execute_1269(char*, char *);
IKI_DLLESPEC extern void execute_1270(char*, char *);
IKI_DLLESPEC extern void execute_1271(char*, char *);
IKI_DLLESPEC extern void execute_1272(char*, char *);
IKI_DLLESPEC extern void execute_1273(char*, char *);
IKI_DLLESPEC extern void vlog_simple_process_execute_0_fast_no_reg_no_agg(char*, char*, char*);
IKI_DLLESPEC extern void execute_1244(char*, char *);
IKI_DLLESPEC extern void execute_1245(char*, char *);
IKI_DLLESPEC extern void execute_1246(char*, char *);
IKI_DLLESPEC extern void execute_1247(char*, char *);
IKI_DLLESPEC extern void execute_1248(char*, char *);
IKI_DLLESPEC extern void execute_1249(char*, char *);
IKI_DLLESPEC extern void execute_1250(char*, char *);
IKI_DLLESPEC extern void execute_1251(char*, char *);
IKI_DLLESPEC extern void execute_1252(char*, char *);
IKI_DLLESPEC extern void execute_1253(char*, char *);
IKI_DLLESPEC extern void execute_1254(char*, char *);
IKI_DLLESPEC extern void execute_14(char*, char *);
IKI_DLLESPEC extern void execute_38(char*, char *);
IKI_DLLESPEC extern void execute_39(char*, char *);
IKI_DLLESPEC extern void execute_40(char*, char *);
IKI_DLLESPEC extern void execute_1739(char*, char *);
IKI_DLLESPEC extern void execute_1740(char*, char *);
IKI_DLLESPEC extern void execute_1741(char*, char *);
IKI_DLLESPEC extern void execute_1742(char*, char *);
IKI_DLLESPEC extern void execute_1743(char*, char *);
IKI_DLLESPEC extern void execute_1744(char*, char *);
IKI_DLLESPEC extern void execute_1745(char*, char *);
IKI_DLLESPEC extern void execute_1746(char*, char *);
IKI_DLLESPEC extern void execute_1747(char*, char *);
IKI_DLLESPEC extern void execute_1748(char*, char *);
IKI_DLLESPEC extern void execute_1749(char*, char *);
IKI_DLLESPEC extern void execute_1750(char*, char *);
IKI_DLLESPEC extern void execute_1751(char*, char *);
IKI_DLLESPEC extern void execute_1752(char*, char *);
IKI_DLLESPEC extern void execute_1753(char*, char *);
IKI_DLLESPEC extern void execute_1754(char*, char *);
IKI_DLLESPEC extern void execute_1805(char*, char *);
IKI_DLLESPEC extern void execute_1806(char*, char *);
IKI_DLLESPEC extern void execute_1807(char*, char *);
IKI_DLLESPEC extern void execute_1808(char*, char *);
IKI_DLLESPEC extern void execute_1809(char*, char *);
IKI_DLLESPEC extern void execute_1934(char*, char *);
IKI_DLLESPEC extern void execute_1935(char*, char *);
IKI_DLLESPEC extern void execute_1936(char*, char *);
IKI_DLLESPEC extern void execute_1937(char*, char *);
IKI_DLLESPEC extern void execute_1222(char*, char *);
IKI_DLLESPEC extern void execute_1943(char*, char *);
IKI_DLLESPEC extern void execute_1944(char*, char *);
IKI_DLLESPEC extern void execute_1945(char*, char *);
IKI_DLLESPEC extern void execute_1946(char*, char *);
IKI_DLLESPEC extern void execute_1947(char*, char *);
IKI_DLLESPEC extern void execute_1948(char*, char *);
IKI_DLLESPEC extern void execute_1221(char*, char *);
IKI_DLLESPEC extern void execute_1942(char*, char *);
IKI_DLLESPEC extern void execute_1235(char*, char *);
IKI_DLLESPEC extern void execute_1236(char*, char *);
IKI_DLLESPEC extern void execute_1237(char*, char *);
IKI_DLLESPEC extern void execute_1238(char*, char *);
IKI_DLLESPEC extern void execute_1994(char*, char *);
IKI_DLLESPEC extern void execute_1995(char*, char *);
IKI_DLLESPEC extern void execute_1996(char*, char *);
IKI_DLLESPEC extern void execute_1997(char*, char *);
IKI_DLLESPEC extern void execute_1998(char*, char *);
IKI_DLLESPEC extern void execute_1999(char*, char *);
IKI_DLLESPEC extern void vlog_transfunc_eventcallback(char*, char*, unsigned, unsigned, unsigned, char *);
IKI_DLLESPEC extern void transaction_143(char*, char*, unsigned, unsigned, unsigned);
IKI_DLLESPEC extern void transaction_144(char*, char*, unsigned, unsigned, unsigned);
IKI_DLLESPEC extern void transaction_0(char*, char*, unsigned, unsigned, unsigned);
funcp funcTab[133] = {(funcp)execute_2, (funcp)execute_1224, (funcp)execute_1233, (funcp)execute_1978, (funcp)execute_1979, (funcp)execute_1980, (funcp)execute_1981, (funcp)execute_1982, (funcp)execute_1983, (funcp)execute_1984, (funcp)execute_1985, (funcp)execute_1986, (funcp)execute_1987, (funcp)execute_1988, (funcp)execute_1989, (funcp)execute_1990, (funcp)execute_1991, (funcp)execute_1992, (funcp)execute_1993, (funcp)execute_1223, (funcp)execute_1239, (funcp)execute_1958, (funcp)vlog_const_rhs_process_execute_0_fast_for_reg, (funcp)execute_1960, (funcp)execute_1961, (funcp)execute_1962, (funcp)execute_1963, (funcp)execute_1964, (funcp)execute_1965, (funcp)execute_1966, (funcp)execute_1967, (funcp)execute_1968, (funcp)execute_1969, (funcp)execute_1970, (funcp)execute_1971, (funcp)execute_1972, (funcp)execute_1973, (funcp)execute_1974, (funcp)execute_1975, (funcp)execute_1976, (funcp)execute_1977, (funcp)execute_8, (funcp)execute_1240, (funcp)execute_1241, (funcp)execute_1949, (funcp)execute_1950, (funcp)execute_1951, (funcp)execute_1952, (funcp)execute_1953, (funcp)execute_1954, (funcp)execute_1955, (funcp)execute_1956, (funcp)execute_1957, (funcp)execute_1216, (funcp)execute_1217, (funcp)execute_1218, (funcp)execute_1242, (funcp)execute_1938, (funcp)execute_1939, (funcp)execute_1940, (funcp)execute_1941, (funcp)execute_1803, (funcp)execute_1804, (funcp)execute_1268, (funcp)execute_1269, (funcp)execute_1270, (funcp)execute_1271, (funcp)execute_1272, (funcp)execute_1273, (funcp)vlog_simple_process_execute_0_fast_no_reg_no_agg, (funcp)execute_1244, (funcp)execute_1245, (funcp)execute_1246, (funcp)execute_1247, (funcp)execute_1248, (funcp)execute_1249, (funcp)execute_1250, (funcp)execute_1251, (funcp)execute_1252, (funcp)execute_1253, (funcp)execute_1254, (funcp)execute_14, (funcp)execute_38, (funcp)execute_39, (funcp)execute_40, (funcp)execute_1739, (funcp)execute_1740, (funcp)execute_1741, (funcp)execute_1742, (funcp)execute_1743, (funcp)execute_1744, (funcp)execute_1745, (funcp)execute_1746, (funcp)execute_1747, (funcp)execute_1748, (funcp)execute_1749, (funcp)execute_1750, (funcp)execute_1751, (funcp)execute_1752, (funcp)execute_1753, (funcp)execute_1754, (funcp)execute_1805, (funcp)execute_1806, (funcp)execute_1807, (funcp)execute_1808, (funcp)execute_1809, (funcp)execute_1934, (funcp)execute_1935, (funcp)execute_1936, (funcp)execute_1937, (funcp)execute_1222, (funcp)execute_1943, (funcp)execute_1944, (funcp)execute_1945, (funcp)execute_1946, (funcp)execute_1947, (funcp)execute_1948, (funcp)execute_1221, (funcp)execute_1942, (funcp)execute_1235, (funcp)execute_1236, (funcp)execute_1237, (funcp)execute_1238, (funcp)execute_1994, (funcp)execute_1995, (funcp)execute_1996, (funcp)execute_1997, (funcp)execute_1998, (funcp)execute_1999, (funcp)vlog_transfunc_eventcallback, (funcp)transaction_143, (funcp)transaction_144, (funcp)transaction_0};
const int NumRelocateId= 133;

void relocate(char *dp)
{
	iki_relocate(dp, "xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.reloc",  (void **)funcTab, 133);

	/*Populate the transaction function pointer field in the whole net structure */
}

void sensitize(char *dp)
{
	iki_sensitize(dp, "xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.reloc");
}

	// Initialize Verilog nets in mixed simulation, for the cases when the value at time 0 should be propagated from the mixed language Vhdl net

void wrapper_func_0(char *dp)

{

}

void simulate(char *dp)
{
		iki_schedule_processes_at_time_zero(dp, "xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.reloc");
	wrapper_func_0(dp);

	iki_execute_processes();

	// Schedule resolution functions for the multiply driven Verilog nets that have strength
	// Schedule transaction functions for the singly driven Verilog nets that have strength

}
#include "iki_bridge.h"
void relocate(char *);

void sensitize(char *);

void simulate(char *);

extern SYSTEMCLIB_IMP_DLLSPEC void local_register_implicit_channel(int, char*);
extern SYSTEMCLIB_IMP_DLLSPEC int xsim_argc_copy ;
extern SYSTEMCLIB_IMP_DLLSPEC char** xsim_argv_copy ;

int main(int argc, char **argv)
{
    iki_heap_initialize("ms", "isimmm", 0, 2147483648) ;
    iki_set_xsimdir_location_if_remapped(argc, argv)  ;
    iki_set_sv_type_file_path_name("xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.svtype");
    iki_set_crvs_dump_file_path_name("xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.crvsdump");
    void* design_handle = iki_create_design("xsim.dir/tb_aes_gcm_core_adapter_behav/xsim.mem", (void *)relocate, (void *)sensitize, (void *)simulate, (void*)0, 0, isimBridge_getWdbWriter(), 0, argc, argv);
     iki_set_rc_trial_count(100);
    (void) design_handle;
    return iki_simulate_design();
}
