-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Package Types, Parameter Constants, and Utility Functions
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;
use work.talos_axi4_pkg.all;
use work.talos_fpu_pkg.all;

entity tb_talos_pkg is
end entity tb_talos_pkg;

architecture sim of tb_talos_pkg is
begin

    process
    begin
        report "[TEST] Starting tb_talos_pkg verification...";

        -- 1. Verify clog2
        assert clog2(1) = 0 report "clog2(1) should be 0" severity failure;
        assert clog2(2) = 1 report "clog2(2) should be 1" severity failure;
        assert clog2(3) = 2 report "clog2(3) should be 2" severity failure;
        assert clog2(4) = 2 report "clog2(4) should be 2" severity failure;
        assert clog2(32) = 5 report "clog2(32) should be 5" severity failure;
        assert clog2(64) = 6 report "clog2(64) should be 6" severity failure;

        -- 2. Verify boolean conversion helpers
        assert bool_to_sl(true) = '1' report "bool_to_sl(true) should be '1'" severity failure;
        assert bool_to_sl(false) = '0' report "bool_to_sl(false) should be '0'" severity failure;
        assert sl_to_bool('1') report "sl_to_bool('1') should be true" severity failure;
        assert not sl_to_bool('0') report "sl_to_bool('0') should be false" severity failure;

        -- 3. Verify Microarchitectural Dimensions
        assert XLEN = 32 report "XLEN mismatch" severity failure;
        assert PHYS_REG_COUNT = 64 report "PHYS_REG_COUNT mismatch" severity failure;
        assert ROB_DEPTH = 32 report "ROB_DEPTH mismatch" severity failure;
        assert RS_ALU_DEPTH = 8 report "RS_ALU_DEPTH mismatch" severity failure;
        assert LQ_DEPTH = 16 report "LQ_DEPTH mismatch" severity failure;
        assert SQ_DEPTH = 16 report "SQ_DEPTH mismatch" severity failure;
        assert CKPT_COUNT = 8 report "CKPT_COUNT mismatch" severity failure;
        assert MSHR_DEPTH = 4 report "MSHR_DEPTH mismatch" severity failure;

        report "[PASS] tb_talos_pkg verification successful.";
        wait;
    end process;

end architecture sim;
