-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Rename: Physical Register Free List with Speculative Dual-Allocation
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_free_list is
    generic (
        TOTAL_PREGS : integer := 64;
        TAG_BITS    : integer := 6
    );
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;

        -- Allocation Interface (Rename Stage)
        alloc_req0        : in  std_logic;
        alloc_req1        : in  std_logic;
        alloc_tag0        : out std_logic_vector(TAG_BITS-1 downto 0);
        alloc_tag1        : out std_logic_vector(TAG_BITS-1 downto 0);
        alloc_ready       : out std_logic;

        -- Commit Free Interface (Retirement Stage)
        commit_free_val0  : in  std_logic;
        commit_free_tag0  : in  std_logic_vector(TAG_BITS-1 downto 0);
        commit_free_val1  : in  std_logic;
        commit_free_tag1  : in  std_logic_vector(TAG_BITS-1 downto 0);

        -- Checkpoint / Recovery Interface (Branch Recovery)
        restore_valid     : in  std_logic;
        restore_mask      : in  std_logic_vector(TOTAL_PREGS-1 downto 0);
        current_mask      : out std_logic_vector(TOTAL_PREGS-1 downto 0)
    );
end entity talos_free_list;

architecture rtl of talos_free_list is

    -- Free bitmask: '1' indicates the physical register is free for allocation
    -- Physical registers 0 to 31 are initially bound to architectural x0-x31.
    -- Physical registers 32 to 63 are free. Physical register 0 is never allocated (hardwired x0).
    signal free_mask_reg : std_logic_vector(TOTAL_PREGS-1 downto 0) := (
        63 downto 32 => '1',
        31 downto 0  => '0'
    );

    signal cand_tag0 : integer range 0 to TOTAL_PREGS-1;
    signal cand_tag1 : integer range 0 to TOTAL_PREGS-1;
    signal found0    : boolean;
    signal found1    : boolean;

begin

    current_mask <= free_mask_reg;

    -- Combinational search for two available free physical registers
    process(free_mask_reg)
        variable f0, f1   : boolean;
        variable idx0, idx1 : integer range 0 to TOTAL_PREGS-1;
    begin
        f0   := false;
        f1   := false;
        idx0 := 0;
        idx1 := 0;

        for i in 1 to TOTAL_PREGS-1 loop
            if free_mask_reg(i) = '1' then
                if not f0 then
                    idx0 := i;
                    f0   := true;
                elsif not f1 then
                    idx1 := i;
                    f1   := true;
                end if;
            end if;
        end loop;

        cand_tag0 <= idx0;
        cand_tag1 <= idx1;
        found0    <= f0;
        found1    <= f1;
    end process;

    alloc_tag0 <= std_logic_vector(to_unsigned(cand_tag0, TAG_BITS));
    alloc_tag1 <= std_logic_vector(to_unsigned(cand_tag1, TAG_BITS));

    -- Ready if requested slots can be satisfied
    process(alloc_req0, alloc_req1, found0, found1)
    begin
        if alloc_req0 = '1' and alloc_req1 = '1' then
            alloc_ready <= bool_to_sl(found0 and found1);
        elsif alloc_req0 = '1' or alloc_req1 = '1' then
            alloc_ready <= bool_to_sl(found0);
        else
            alloc_ready <= '1';
        end if;
    end process;

    -- State update process
    process(clk, rst_n)
        variable mask_next : std_logic_vector(TOTAL_PREGS-1 downto 0);
    begin
        if rst_n = '0' then
            free_mask_reg <= (63 downto 32 => '1', 31 downto 0 => '0');
        elsif rising_edge(clk) then
            if restore_valid = '1' then
                free_mask_reg <= restore_mask;
            else
                mask_next := free_mask_reg;

                -- 1. Free registers retiring at commit
                if commit_free_val0 = '1' and to_integer(unsigned(commit_free_tag0)) /= 0 then
                    mask_next(to_integer(unsigned(commit_free_tag0))) := '1';
                end if;

                if commit_free_val1 = '1' and to_integer(unsigned(commit_free_tag1)) /= 0 then
                    mask_next(to_integer(unsigned(commit_free_tag1))) := '1';
                end if;

                -- 2. Allocate registers consumed at rename
                if alloc_req0 = '1' and found0 then
                    mask_next(cand_tag0) := '0';
                end if;

                if alloc_req1 = '1' and found1 then
                    mask_next(cand_tag1) := '0';
                end if;

                free_mask_reg <= mask_next;
            end if;
        end if;
    end process;

end architecture rtl;
