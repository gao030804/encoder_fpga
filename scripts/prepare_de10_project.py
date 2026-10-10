"""Generate an isolated Quartus project with verified DE10 reference pin names."""
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    out=ROOT/'build/de10_sdram';out.mkdir(parents=True,exist_ok=True)
    pins=(ROOT/'rtl/fpga/constraints/de10_lite_sdram_pins.qsf').read_text()
    sources=[s for s in (ROOT/'scripts/fpga_system_files.f').read_text().splitlines() if s.endswith(('.v','.sv'))]
    sources+=['rtl/fpga/de10_lite_board_top.v']
    qsf='''set_global_assignment -name FAMILY "MAX 10"
set_global_assignment -name DEVICE 10M50DAF484C7G
set_global_assignment -name TOP_LEVEL_ENTITY de10_lite_board_top
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name VERILOG_MACRO FPGA_TARGET
set_global_assignment -name SEARCH_PATH ../../rtl/flash
set_global_assignment -name SDC_FILE ../../rtl/fpga/constraints/de10_lite_sdram.sdc
set_global_assignment -name NUM_PARALLEL_PROCESSORS 2
'''
    for s in sources:qsf+=f'set_global_assignment -name SYSTEMVERILOG_FILE "../../{s}"\n'
    qsf+=pins
    (out/'de10_sdram.qsf').write_text(qsf);(out/'de10_sdram.qpf').write_text('PROJECT_REVISION = "de10_sdram"\n')
    print(out)
if __name__=='__main__':main()
