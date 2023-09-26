-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: 2-Way Set-Associative Branch Target Buffer (BTB)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_btb is
    generic (
        SETS        : integer := 128;
        INDEX_BITS  : integer := 7;
        TAG_BITS    : integer := 23
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        -- Query Interface (Fetch Stage)
        fetch_pc        : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        hit             : out std_logic;
        target_pc       : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        is_call         : out std_logic;
        is_return       : out std_logic;

        -- Update Interface (Execution / Branch Resolution)
        update_valid    : in  std_logic;
        update_pc       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        update_target   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        update_is_call  : in  std_logic;
        update_is_return: in  std_logic
    );
end entity talos_btb;

architecture rtl of talos_btb is

    type btb_entry_t is record
        valid     : std_logic;
        tag       : std_logic_vector(TAG_BITS-1 downto 0);
        target    : std_logic_vector(ADDR_WIDTH-1 downto 0);
        is_call   : std_logic;
        is_return : std_logic;
    end record btb_entry_t;

    type btb_set_t is array (0 to 1) of btb_entry_t;
    type btb_table_t is array (0 to SETS-1) of btb_set_t;

    signal btb_table : btb_table_t := (others => (others => (
        valid     => '0',
        tag       => (others => '0'),
        target    => (others => '0'),
        is_call   => '0',
        is_return => '0'
    )));

    signal lru_bits  : std_logic_vector(SETS-1 downto 0) := (others => '0');

    -- Extraction helpers
    signal query_idx : integer range 0 to SETS-1;
    signal query_tag : std_logic_vector(TAG_BITS-1 downto 0);

begin

    query_idx <= to_integer(unsigned(fetch_pc(INDEX_BITS+1 downto 2)));
    query_tag <= fetch_pc(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);

    -- Combinational lookup across both ways
    process(query_idx, query_tag, btb_table)
        variable way0 : btb_entry_t;
        variable way1 : btb_entry_t;
    begin
        way0 := btb_table(query_idx)(0);
        way1 := btb_table(query_idx)(1);

        if way0.valid = '1' and way0.tag = query_tag then
            hit       <= '1';
            target_pc <= way0.target;
            is_call   <= way0.is_call;
            is_return <= way0.is_return;
        elsif way1.valid = '1' and way1.tag = query_tag then
            hit       <= '1';
            target_pc <= way1.target;
            is_call   <= way1.is_call;
            is_return <= way1.is_return;
        else
            hit       <= '0';
            target_pc <= (others => '0');
            is_call   <= '0';
            is_return <= '0';
        end if;
    end process;

    -- Update and replacement process
    process(clk, rst_n)
        variable up_idx    : integer range 0 to SETS-1;
        variable up_tag    : std_logic_vector(TAG_BITS-1 downto 0);
        variable alloc_way : integer range 0 to 1;
    begin
        if rst_n = '0' then
            for s in 0 to SETS-1 loop
                btb_table(s)(0).valid <= '0';
                btb_table(s)(1).valid <= '0';
            end loop;
            lru_bits <= (others => '0');
        elsif rising_edge(clk) then
            if update_valid = '1' then
                up_idx := to_integer(unsigned(update_pc(INDEX_BITS+1 downto 2)));
                up_tag := update_pc(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);

                -- Check if entry already exists in Way 0 or Way 1
                if btb_table(up_idx)(0).valid = '1' and btb_table(up_idx)(0).tag = up_tag then
                    alloc_way := 0;
                elsif btb_table(up_idx)(1).valid = '1' and btb_table(up_idx)(1).tag = up_tag then
                    alloc_way := 1;
                else
                    -- Allocate according to LRU bit (0: replace way 0, 1: replace way 1)
                    if lru_bits(up_idx) = '0' then
                        alloc_way := 0;
                    else
                        alloc_way := 1;
                    end if;
                end if;

                -- Write new target and metadata
                btb_table(up_idx)(alloc_way).valid     <= '1';
                btb_table(up_idx)(alloc_way).tag       <= up_tag;
                btb_table(up_idx)(alloc_way).target    <= update_target;
                btb_table(up_idx)(alloc_way).is_call   <= update_is_call;
                btb_table(up_idx)(alloc_way).is_return <= update_is_return;

                -- Toggle LRU bit
                if alloc_way = 0 then
                    lru_bits(up_idx) <= '1';
                else
                    lru_bits(up_idx) <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
