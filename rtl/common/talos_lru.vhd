-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: Parameterized Tree-Based Pseudo-LRU Replacement Engine
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_lru is
    generic (
        WAYS : integer := 4 -- Supported: 2 or 4
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        req_access : in  std_logic;
        hit_way    : in  std_logic_vector(1 downto 0); -- Way accessed on hit/update
        victim     : out std_logic_vector(1 downto 0)  -- Candidate way for replacement
    );
end entity talos_lru;

architecture rtl of talos_lru is

    -- For 4-way set associative:
    -- Bit 0: Root node (0: left branch way 0/1, 1: right branch way 2/3)
    -- Bit 1: Left node (0: way 0, 1: way 1)
    -- Bit 2: Right node (0: way 2, 1: way 3)
    signal tree_bits : std_logic_vector(2 downto 0) := (others => '0');

begin

    gen_2way: if WAYS = 2 generate
        -- 2-way: single bit
        victim <= "0" & (not tree_bits(0));

        process(clk, rst_n)
        begin
            if rst_n = '0' then
                tree_bits(0) <= '0';
            elsif rising_edge(clk) then
                if req_access = '1' then
                    tree_bits(0) <= hit_way(0);
                end if;
            end if;
        end process;
    end generate gen_2way;

    gen_4way: if WAYS = 4 generate
        -- 4-way Tree-PLRU replacement decision
        process(tree_bits)
        begin
            if tree_bits(0) = '0' then
                -- Go right (left was recently used)
                if tree_bits(2) = '0' then
                    victim <= "11"; -- Way 3
                else
                    victim <= "10"; -- Way 2
                end if;
            else
                -- Go left (right was recently used)
                if tree_bits(1) = '0' then
                    victim <= "01"; -- Way 1
                else
                    victim <= "00"; -- Way 0
                end if;
            end if;
        end process;

        -- Update tree bits on access
        process(clk, rst_n)
        begin
            if rst_n = '0' then
                tree_bits <= (others => '0');
            elsif rising_edge(clk) then
                if req_access = '1' then
                    case hit_way is
                        when "00" =>
                            tree_bits(0) <= '0';
                            tree_bits(1) <= '0';
                        when "01" =>
                            tree_bits(0) <= '0';
                            tree_bits(1) <= '1';
                        when "10" =>
                            tree_bits(0) <= '1';
                            tree_bits(2) <= '0';
                        when "11" =>
                            tree_bits(0) <= '1';
                            tree_bits(2) <= '1';
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end process;
    end generate gen_4way;

end architecture rtl;
