-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: Multi-Channel Common Data Bus (CDB) Priority Arbiter and Broadcast
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_cdb_arbiter is
    port (
        -- Port 0: ALU0 and Branch Unit
        alu0_val       : in  std_logic;
        alu0_tag       : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alu0_rob_idx   : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alu0_res       : in  std_logic_vector(XLEN-1 downto 0);
        alu0_exc       : in  std_logic;
        alu0_exc_cause : in  std_logic_vector(4 downto 0);

        -- Port 1: ALU1 Unit
        alu1_val       : in  std_logic;
        alu1_tag       : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alu1_rob_idx   : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alu1_res       : in  std_logic_vector(XLEN-1 downto 0);

        -- Port 2: Multiplier
        mul_val        : in  std_logic;
        mul_tag        : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        mul_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        mul_res        : in  std_logic_vector(XLEN-1 downto 0);

        -- Port 3: Divider
        div_val        : in  std_logic;
        div_tag        : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        div_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        div_res        : in  std_logic_vector(XLEN-1 downto 0);

        -- Port 4: Memory (Load Execution from LSQ / D-Cache)
        mem_val        : in  std_logic;
        mem_tag        : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        mem_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        mem_res        : in  std_logic_vector(XLEN-1 downto 0);
        mem_exc        : in  std_logic;
        mem_exc_cause  : in  std_logic_vector(4 downto 0);

        -- Port 5: FPU Pipeline
        fpu_val        : in  std_logic;
        fpu_tag        : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        fpu_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        fpu_res        : in  std_logic_vector(XLEN-1 downto 0);

        -- Unified Broadcast Common Data Bus (5 Channels)
        cdb_out        : out cdb_bus_t
    );
end entity talos_cdb_arbiter;

architecture rtl of talos_cdb_arbiter is
begin

    -- Channel 0: Dedicated ALU0 / Branch Unit
    cdb_out(0).valid     <= alu0_val;
    cdb_out(0).phys_tag  <= alu0_tag;
    cdb_out(0).rob_idx   <= alu0_rob_idx;
    cdb_out(0).value     <= alu0_res;
    cdb_out(0).exception <= alu0_exc;
    cdb_out(0).exc_cause <= alu0_exc_cause;

    -- Channel 1: Dedicated ALU1 Unit
    cdb_out(1).valid     <= alu1_val;
    cdb_out(1).phys_tag  <= alu1_tag;
    cdb_out(1).rob_idx   <= alu1_rob_idx;
    cdb_out(1).value     <= alu1_res;
    cdb_out(1).exception <= '0';
    cdb_out(1).exc_cause <= (others => '0');

    -- Channel 2: Multiplier / Divider (Multiplier has priority)
    process(mul_val, mul_tag, mul_rob_idx, mul_res, div_val, div_tag, div_rob_idx, div_res)
    begin
        if mul_val = '1' then
            cdb_out(2).valid     <= '1';
            cdb_out(2).phys_tag  <= mul_tag;
            cdb_out(2).rob_idx   <= mul_rob_idx;
            cdb_out(2).value     <= mul_res;
            cdb_out(2).exception <= '0';
            cdb_out(2).exc_cause <= (others => '0');
        elsif div_val = '1' then
            cdb_out(2).valid     <= '1';
            cdb_out(2).phys_tag  <= div_tag;
            cdb_out(2).rob_idx   <= div_rob_idx;
            cdb_out(2).value     <= div_res;
            cdb_out(2).exception <= '0';
            cdb_out(2).exc_cause <= (others => '0');
        else
            cdb_out(2) <= CDB_ENTRY_ZERO;
        end if;
    end process;

    -- Channel 3: Dedicated Memory Subsystem (Load Data)
    cdb_out(3).valid     <= mem_val;
    cdb_out(3).phys_tag  <= mem_tag;
    cdb_out(3).rob_idx   <= mem_rob_idx;
    cdb_out(3).value     <= mem_res;
    cdb_out(3).exception <= mem_exc;
    cdb_out(3).exc_cause <= mem_exc_cause;

    -- Channel 4: Dedicated Floating-Point Unit
    cdb_out(4).valid     <= fpu_val;
    cdb_out(4).phys_tag  <= fpu_tag;
    cdb_out(4).rob_idx   <= fpu_rob_idx;
    cdb_out(4).value     <= fpu_res;
    cdb_out(4).exception <= '0';
    cdb_out(4).exc_cause <= (others => '0');

end architecture rtl;
