-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: Parameterized Priority Encoder and One-Hot Arbiter
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_priority_enc is
    generic (
        WIDTH      : integer := 8;
        INDEX_BITS : integer := 3;
        LOWEST_PRI : boolean := true -- True: lowest index has highest priority
    );
    port (
        req        : in  std_logic_vector(WIDTH-1 downto 0);
        grant      : out std_logic_vector(WIDTH-1 downto 0);
        grant_idx  : out std_logic_vector(INDEX_BITS-1 downto 0);
        valid      : out std_logic
    );
end entity talos_priority_enc;

architecture rtl of talos_priority_enc is
begin

    process(req)
        variable g     : std_logic_vector(WIDTH-1 downto 0);
        variable found : boolean;
        variable idx   : integer range 0 to WIDTH-1;
    begin
        g     := (others => '0');
        found := false;
        idx   := 0;

        if LOWEST_PRI then
            -- Search from index 0 upward
            for i in 0 to WIDTH-1 loop
                if req(i) = '1' and not found then
                    g(i)  := '1';
                    idx   := i;
                    found := true;
                end if;
            end loop;
        else
            -- Search from highest index downward
            for i in WIDTH-1 downto 0 loop
                if req(i) = '1' and not found then
                    g(i)  := '1';
                    idx   := i;
                    found := true;
                end if;
            end loop;
        end if;

        grant <= g;
        grant_idx <= std_logic_vector(to_unsigned(idx, INDEX_BITS));
        if found then
            valid <= '1';
        else
            valid <= '0';
        end if;
    end process;

end architecture rtl;
