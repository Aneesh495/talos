-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Common Hardware: Gray-Coded Dual-Clock Asynchronous CDC FIFO
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity talos_async_fifo is
    generic (
        DATA_WIDTH : integer := 32;
        ADDR_WIDTH : integer := 4  -- Depth = 2**ADDR_WIDTH = 16
    );
    port (
        -- Write Clock Domain
        wr_clk     : in  std_logic;
        wr_rst_n   : in  std_logic;
        wr_en      : in  std_logic;
        wr_data    : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_full    : out std_logic;

        -- Read Clock Domain
        rd_clk     : in  std_logic;
        rd_rst_n   : in  std_logic;
        rd_en      : in  std_logic;
        rd_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_empty   : out std_logic
    );
end entity talos_async_fifo;

architecture rtl of talos_async_fifo is

    constant FIFO_DEPTH : integer := 2**ADDR_WIDTH;

    type mem_array_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem_array : mem_array_t := (others => (others => '0'));

    -- Write domain signals
    signal wr_bin          : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_bin_next     : unsigned(ADDR_WIDTH downto 0);
    signal wr_gray         : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_gray_next    : std_logic_vector(ADDR_WIDTH downto 0);
    signal wr_full_val     : std_logic;

    -- Synchronizers: rd_gray into wr_clk domain
    signal rd_gray_sync1   : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_gray_sync2   : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');

    -- Read domain signals
    signal rd_bin          : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_bin_next     : unsigned(ADDR_WIDTH downto 0);
    signal rd_gray         : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
    signal rd_gray_next    : std_logic_vector(ADDR_WIDTH downto 0);
    signal rd_empty_val    : std_logic;

    -- Synchronizers: wr_gray into rd_clk domain
    signal wr_gray_sync1   : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');
    signal wr_gray_sync2   : std_logic_vector(ADDR_WIDTH downto 0) := (others => '0');

    -- Gray code conversion helper
    function bin_to_gray(b : unsigned) return std_logic_vector is
        variable bv : std_logic_vector(b'range);
        variable g  : std_logic_vector(b'range);
    begin
        bv := std_logic_vector(b);
        g(b'high) := bv(b'high);
        for i in b'high-1 downto 0 loop
            g(i) := bv(i+1) xor bv(i);
        end loop;
        return g;
    end function bin_to_gray;

begin

    -- -------------------------------------------------------------------------
    -- Memory Array Write and Read
    -- -------------------------------------------------------------------------
    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_en = '1' and wr_full_val = '0' then
                mem_array(to_integer(wr_bin(ADDR_WIDTH-1 downto 0))) <= wr_data;
            end if;
        end if;
    end process;

    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_en = '1' and rd_empty_val = '0' then
                rd_data <= mem_array(to_integer(rd_bin(ADDR_WIDTH-1 downto 0)));
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Write Domain Logic
    -- -------------------------------------------------------------------------
    wr_bin_next  <= wr_bin + 1 when (wr_en = '1' and wr_full_val = '0') else wr_bin;
    wr_gray_next <= bin_to_gray(wr_bin_next);

    -- Full when MSBs differ and remaining bits match
    process(wr_gray_next, rd_gray_sync2)
    begin
        if (wr_gray_next(ADDR_WIDTH) /= rd_gray_sync2(ADDR_WIDTH)) and
           (wr_gray_next(ADDR_WIDTH-1) /= rd_gray_sync2(ADDR_WIDTH-1)) and
           (wr_gray_next(ADDR_WIDTH-2 downto 0) = rd_gray_sync2(ADDR_WIDTH-2 downto 0)) then
            wr_full_val <= '1';
        else
            wr_full_val <= '0';
        end if;
    end process;

    wr_full <= wr_full_val;

    process(wr_clk, wr_rst_n)
    begin
        if wr_rst_n = '0' then
            wr_bin         <= (others => '0');
            wr_gray        <= (others => '0');
            rd_gray_sync1  <= (others => '0');
            rd_gray_sync2  <= (others => '0');
        elsif rising_edge(wr_clk) then
            wr_bin         <= wr_bin_next;
            wr_gray        <= wr_gray_next;
            rd_gray_sync1  <= rd_gray;
            rd_gray_sync2  <= rd_gray_sync1;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Read Domain Logic
    -- -------------------------------------------------------------------------
    rd_bin_next  <= rd_bin + 1 when (rd_en = '1' and rd_empty_val = '0') else rd_bin;
    rd_gray_next <= bin_to_gray(rd_bin_next);

    rd_empty_val <= '1' when (rd_gray = wr_gray_sync2) else '0';
    rd_empty     <= rd_empty_val;

    process(rd_clk, rd_rst_n)
    begin
        if rd_rst_n = '0' then
            rd_bin         <= (others => '0');
            rd_gray        <= (others => '0');
            wr_gray_sync1  <= (others => '0');
            wr_gray_sync2  <= (others => '0');
        elsif rising_edge(rd_clk) then
            rd_bin         <= rd_bin_next;
            rd_gray        <= rd_gray_next;
            wr_gray_sync1  <= wr_gray;
            wr_gray_sync2  <= wr_gray_sync1;
        end if;
    end process;

end architecture rtl;
