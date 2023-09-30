-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: 16-Entry Return Address Stack (RAS) with Speculative Pointer Repair
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_ras is
    generic (
        DEPTH      : integer := 16;
        INDEX_BITS : integer := 4
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        -- Speculative Fetch Operations
        push_valid      : in  std_logic;
        push_addr       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        pop_valid       : in  std_logic;
        pop_addr        : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        pop_valid_out   : out std_logic;

        -- Current Speculative TOS Pointer (for branch checkpointing)
        current_tos     : out std_logic_vector(INDEX_BITS-1 downto 0);

        -- Misprediction Recovery Interface
        restore_valid   : in  std_logic;
        restore_tos     : in  std_logic_vector(INDEX_BITS-1 downto 0)
    );
end entity talos_ras;

architecture rtl of talos_ras is

    type stack_array_t is array (0 to DEPTH-1) of std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal stack : stack_array_t := (others => (others => '0'));

    signal tos_ptr : unsigned(INDEX_BITS-1 downto 0) := (others => '0');

begin

    current_tos <= std_logic_vector(tos_ptr);

    -- Combinational peek at Top-of-Stack
    process(tos_ptr, stack)
        variable peek_idx : integer range 0 to DEPTH-1;
    begin
        peek_idx := to_integer(tos_ptr - 1);
        pop_addr <= stack(peek_idx);
        if tos_ptr /= 0 then
            pop_valid_out <= '1';
        else
            pop_valid_out <= '0';
        end if;
    end process;

    -- Stack management process
    process(clk, rst_n)
        variable next_tos : unsigned(INDEX_BITS-1 downto 0);
    begin
        if rst_n = '0' then
            tos_ptr <= (others => '0');
            stack   <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if restore_valid = '1' then
                tos_ptr <= unsigned(restore_tos);
            else
                next_tos := tos_ptr;

                -- Simultaneous push and pop replaces top entry without changing pointer
                if push_valid = '1' and pop_valid = '1' then
                    stack(to_integer(tos_ptr - 1)) <= push_addr;
                elsif push_valid = '1' then
                    stack(to_integer(tos_ptr)) <= push_addr;
                    next_tos := tos_ptr + 1;
                elsif pop_valid = '1' and tos_ptr /= 0 then
                    next_tos := tos_ptr - 1;
                end if;

                tos_ptr <= next_tos;
            end if;
        end if;
    end process;

end architecture rtl;
