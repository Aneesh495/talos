-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Rename: Committed Architectural Register Alias Table (cRAT)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_crat is
    generic (
        ARCH_REGS : integer := 32;
        TAG_BITS  : integer := 6
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        -- Commit Update 0 (from ROB Retirement)
        commit_val0     : in  std_logic;
        commit_rd_arch0 : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys0 : in  std_logic_vector(TAG_BITS-1 downto 0);

        -- Commit Update 1 (from ROB Retirement)
        commit_val1     : in  std_logic;
        commit_rd_arch1 : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys1 : in  std_logic_vector(TAG_BITS-1 downto 0);

        -- Architectural Snapshot for Exception Recovery
        crat_table_out  : out std_logic_vector(ARCH_REGS*TAG_BITS-1 downto 0)
    );
end entity talos_crat;

architecture rtl of talos_crat is

    type crat_array_t is array (0 to ARCH_REGS-1) of std_logic_vector(TAG_BITS-1 downto 0);

    function init_crat return crat_array_t is
        variable r : crat_array_t;
    begin
        for i in 0 to ARCH_REGS-1 loop
            r(i) := std_logic_vector(to_unsigned(i, TAG_BITS));
        end loop;
        return r;
    end function init_crat;

    signal crat_table : crat_array_t := init_crat;

begin

    -- Flatten table for exception restoration
    process(crat_table)
        variable flat : std_logic_vector(ARCH_REGS*TAG_BITS-1 downto 0);
    begin
        for i in 0 to ARCH_REGS-1 loop
            flat((i+1)*TAG_BITS-1 downto i*TAG_BITS) := crat_table(i);
        end loop;
        crat_table_out <= flat;
    end process;

    process(clk, rst_n)
        variable idx0, idx1 : integer range 0 to ARCH_REGS-1;
    begin
        if rst_n = '0' then
            crat_table <= init_crat;
        elsif rising_edge(clk) then
            if commit_val0 = '1' then
                idx0 := to_integer(unsigned(commit_rd_arch0));
                if idx0 /= 0 then
                    crat_table(idx0) <= commit_rd_phys0;
                end if;
            end if;

            if commit_val1 = '1' then
                idx1 := to_integer(unsigned(commit_rd_arch1));
                if idx1 /= 0 then
                    crat_table(idx1) <= commit_rd_phys1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
