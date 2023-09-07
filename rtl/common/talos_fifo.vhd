-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: Synchronous Parameterized Generic FIFO with Watermarks
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_fifo is
    generic (
        DATA_WIDTH        : integer := 32;
        DEPTH             : integer := 16;
        ALMOST_FULL_THRESH : integer := 14;
        ALMOST_EMPTY_THRESH: integer := 2
    );
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;
        flush             : in  std_logic;

        -- Write Interface
        wr_en             : in  std_logic;
        wr_data           : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        full              : out std_logic;
        almost_full       : out std_logic;

        -- Read Interface
        rd_en             : in  std_logic;
        rd_data           : out std_logic_vector(DATA_WIDTH-1 downto 0);
        empty             : out std_logic;
        almost_empty      : out std_logic;

        -- Occupancy Status
        count             : out std_logic_vector(7 downto 0)
    );
end entity talos_fifo;

architecture rtl of talos_fifo is

    type mem_array_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem_reg       : mem_array_t := (others => (others => '0'));

    signal wr_ptr_reg    : integer range 0 to DEPTH-1 := 0;
    signal rd_ptr_reg    : integer range 0 to DEPTH-1 := 0;
    signal count_reg     : integer range 0 to DEPTH   := 0;

    signal full_i        : std_logic;
    signal empty_i       : std_logic;

begin

    full_i  <= '1' when count_reg = DEPTH else '0';
    empty_i <= '1' when count_reg = 0     else '0';

    full         <= full_i;
    empty        <= empty_i;
    almost_full  <= '1' when count_reg >= ALMOST_FULL_THRESH else '0';
    almost_empty <= '1' when count_reg <= ALMOST_EMPTY_THRESH else '0';
    count        <= std_logic_vector(to_unsigned(count_reg, 8));

    rd_data      <= mem_reg(rd_ptr_reg);

    process(clk, rst_n)
        variable next_count : integer range 0 to DEPTH;
    begin
        if rst_n = '0' then
            wr_ptr_reg <= 0;
            rd_ptr_reg <= 0;
            count_reg  <= 0;
            mem_reg    <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if flush = '1' then
                wr_ptr_reg <= 0;
                rd_ptr_reg <= 0;
                count_reg  <= 0;
            else
                next_count := count_reg;

                -- Write transaction
                if wr_en = '1' and full_i = '0' then
                    mem_reg(wr_ptr_reg) <= wr_data;
                    if wr_ptr_reg = DEPTH - 1 then
                        wr_ptr_reg <= 0;
                    else
                        wr_ptr_reg <= wr_ptr_reg + 1;
                    end if;
                    next_count := next_count + 1;
                end if;

                -- Read transaction
                if rd_en = '1' and empty_i = '0' then
                    if rd_ptr_reg = DEPTH - 1 then
                        rd_ptr_reg <= 0;
                    else
                        rd_ptr_reg <= rd_ptr_reg + 1;
                    end if;
                    if not (wr_en = '1' and full_i = '0') then
                        next_count := next_count - 1;
                    else
                        -- Simultaneous write and read leaves count unchanged
                        next_count := count_reg;
                    end if;
                end if;

                count_reg <= next_count;
            end if;
        end if;
    end process;

end architecture rtl;
