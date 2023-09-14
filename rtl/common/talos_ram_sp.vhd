-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: Single-Port Synchronous Block RAM with Byte Enables
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_ram_sp is
    generic (
        DATA_WIDTH : integer := 32;
        ADDR_WIDTH : integer := 10; -- 1024 words
        BYTE_SIZE  : integer := 8
    );
    port (
        clk        : in  std_logic;
        en         : in  std_logic;
        we         : in  std_logic_vector((DATA_WIDTH/BYTE_SIZE)-1 downto 0);
        addr       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        di         : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        do         : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity talos_ram_sp;

architecture rtl of talos_ram_sp is

    constant NUM_BYTES : integer := DATA_WIDTH / BYTE_SIZE;
    constant RAM_DEPTH : integer := 2**ADDR_WIDTH;

    type ram_type is array (0 to RAM_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal ram : ram_type := (others => (others => '0'));

    signal read_data_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            if en = '1' then
                addr_int := to_integer(unsigned(addr));
                for i in 0 to NUM_BYTES-1 loop
                    if we(i) = '1' then
                        ram(addr_int)((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE) <= di((i+1)*BYTE_SIZE-1 downto i*BYTE_SIZE);
                    end if;
                end loop;
                read_data_reg <= ram(addr_int);
            end if;
        end if;
    end process;

    do <= read_data_reg;

end architecture rtl;
