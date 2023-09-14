-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: True Dual-Port Synchronous Block RAM with Byte Enables
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_ram_dp is
    generic (
        DATA_WIDTH : integer := 32;
        ADDR_WIDTH : integer := 10;
        BYTE_SIZE  : integer := 8
    );
    port (
        -- Port A
        clk_a      : in  std_logic;
        en_a       : in  std_logic;
        we_a       : in  std_logic_vector((DATA_WIDTH/BYTE_SIZE)-1 downto 0);
        addr_a     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        di_a       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        do_a       : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Port B
        clk_b      : in  std_logic;
        en_b       : in  std_logic;
        we_b       : in  std_logic_vector((DATA_WIDTH/BYTE_SIZE)-1 downto 0);
        addr_b     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        di_b       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        do_b       : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity talos_ram_dp;

architecture rtl of talos_ram_dp is

    constant NUM_BYTES : integer := DATA_WIDTH / BYTE_SIZE;
    constant RAM_DEPTH : integer := 2**ADDR_WIDTH;

    type ram_type is array (0 to RAM_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ram : ram_type := (others => (others => '0'));

    signal read_data_a_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal read_data_b_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    -- Port A Process
    process(clk_a)
        variable addr_int : integer;
    begin
        if rising_edge(clk_a) then
            if en_a = '1' then
                addr_int := to_integer(unsigned(addr_a));
                for i in 0 to NUM_BYTES-1 loop
                    if we_a(i) = '1' then
                        ram(addr_int)((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE) <= di_a((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE);
                    end if;
                end loop;
                read_data_a_reg <= ram(addr_int);
            end if;
        end if;
    end process;

    do_a <= read_data_a_reg;

    -- Port B Process
    process(clk_b)
        variable addr_int : integer;
    begin
        if rising_edge(clk_b) then
            if en_b = '1' then
                addr_int := to_integer(unsigned(addr_b));
                for i in 0 to NUM_BYTES-1 loop
                    if we_b(i) = '1' then
                        ram(addr_int)((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE) <= di_b((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE);
                    end if;
                end loop;
                read_data_b_reg <= ram(addr_int);
            end if;
        end if;
    end process;

    do_b <= read_data_b_reg;

end architecture rtl;
