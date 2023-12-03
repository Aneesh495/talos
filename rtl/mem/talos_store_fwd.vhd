-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: Byte-Level Speculative Store-to-Load Forwarding Crossbar
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_store_fwd is
    port (
        -- Load Request Parameters
        load_addr       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        load_mask       : in  std_logic_vector(3 downto 0);

        -- Matching Store Parameters from SQ
        store_valid     : in  std_logic;
        store_addr      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        store_data      : in  std_logic_vector(XLEN-1 downto 0);
        store_mask      : in  std_logic_vector(3 downto 0);

        -- Forwarding Outputs
        fwd_match       : out std_logic;
        fwd_complete    : out std_logic;
        fwd_byte_mask   : out std_logic_vector(3 downto 0);
        fwd_result_data : out std_logic_vector(XLEN-1 downto 0)
    );
end entity talos_store_fwd;

architecture rtl of talos_store_fwd is
begin

    process(load_addr, load_mask, store_valid, store_addr, store_data, store_mask)
        variable same_word   : boolean;
        variable byte_match  : std_logic_vector(3 downto 0);
        variable all_bytes   : boolean;
        variable res_data    : std_logic_vector(XLEN-1 downto 0);
    begin
        same_word  := (store_valid = '1') and (load_addr(ADDR_WIDTH-1 downto 2) = store_addr(ADDR_WIDTH-1 downto 2));
        byte_match := (others => '0');
        res_data   := (others => '0');

        if same_word then
            for b in 0 to 3 loop
                if load_mask(b) = '1' and store_mask(b) = '1' then
                    byte_match(b) := '1';
                    res_data((b+1)*8-1 downto b*8) := store_data((b+1)*8-1 downto b*8);
                end if;
            end loop;

            -- Check if all requested load bytes are provided by this store
            all_bytes := true;
            for b in 0 to 3 loop
                if load_mask(b) = '1' and byte_match(b) = '0' then
                    all_bytes := false;
                end if;
            end loop;

            fwd_match       <= bool_to_sl(byte_match /= "0000");
            fwd_complete    <= bool_to_sl(all_bytes);
            fwd_byte_mask   <= byte_match;
            fwd_result_data <= res_data;
        else
            fwd_match       <= '0';
            fwd_complete    <= '0';
            fwd_byte_mask   <= (others => '0');
            fwd_result_data <= (others => '0');
        end if;
    end process;

end architecture rtl;
