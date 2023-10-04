-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: 2-Way 8KB L1 Instruction Cache with 32-Byte Refill FSM
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_icache is
    generic (
        SETS       : integer := 128;
        INDEX_BITS : integer := 7;
        OFFSET_BITS: integer := 5;
        TAG_BITS   : integer := 20
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;
        flush           : in  std_logic;

        -- CPU Fetch Interface
        fetch_req       : in  std_logic;
        fetch_addr      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        fetch_ready     : out std_logic;
        fetch_data0     : out std_logic_vector(INSTR_WIDTH-1 downto 0);
        fetch_data1     : out std_logic_vector(INSTR_WIDTH-1 downto 0);
        fetch_valid0    : out std_logic;
        fetch_valid1    : out std_logic;

        -- AXI4 Memory Interface (Line Refills)
        m_axi_araddr    : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        m_axi_arlen     : out std_logic_vector(7 downto 0);
        m_axi_arsize    : out std_logic_vector(2 downto 0);
        m_axi_arburst   : out std_logic_vector(1 downto 0);
        m_axi_arvalid   : out std_logic;
        m_axi_arready   : in  std_logic;

        m_axi_rdata     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axi_rresp     : in  std_logic_vector(1 downto 0);
        m_axi_rlast     : in  std_logic;
        m_axi_rvalid    : in  std_logic;
        m_axi_rready    : out std_logic
    );
end entity talos_icache;

architecture rtl of talos_icache is

    type line_t is array (0 to 7) of std_logic_vector(31 downto 0);

    type way_data_t is array (0 to SETS-1) of line_t;
    type way_tag_t  is array (0 to SETS-1) of std_logic_vector(TAG_BITS-1 downto 0);
    type way_val_t  is array (0 to SETS-1) of std_logic;

    -- Cache Storage Arrays
    signal data_way0 : way_data_t := (others => (others => (others => '0')));
    signal data_way1 : way_data_t := (others => (others => (others => '0')));
    signal tag_way0  : way_tag_t  := (others => (others => '0'));
    signal tag_way1  : way_tag_t  := (others => (others => '0'));
    signal val_way0  : way_val_t  := (others => '0');
    signal val_way1  : way_val_t  := (others => '0');
    signal plru_bits : std_logic_vector(SETS-1 downto 0) := (others => '0');

    type state_t is (
        ST_IDLE,
        ST_REFILL_ADDR,
        ST_REFILL_DATA,
        ST_REFILL_DONE
    );
    signal state_reg : state_t := ST_IDLE;

    signal refill_line : line_t := (others => (others => '0'));
    signal beat_count  : integer range 0 to 7 := 0;
    signal victim_way  : integer range 0 to 1 := 0;

    -- Address decomposition
    signal req_idx    : integer range 0 to SETS-1;
    signal req_tag    : std_logic_vector(TAG_BITS-1 downto 0);
    signal word_idx   : integer range 0 to 7;

    signal hit_way0   : std_logic;
    signal hit_way1   : std_logic;
    signal cache_hit  : std_logic;

begin

    req_idx  <= to_integer(unsigned(fetch_addr(INDEX_BITS+OFFSET_BITS-1 downto OFFSET_BITS)));
    req_tag  <= fetch_addr(ADDR_WIDTH-1 downto ADDR_WIDTH-TAG_BITS);
    word_idx <= to_integer(unsigned(fetch_addr(4 downto 2)));

    -- Hit evaluation
    hit_way0  <= '1' when (val_way0(req_idx) = '1' and tag_way0(req_idx) = req_tag) else '0';
    hit_way1  <= '1' when (val_way1(req_idx) = '1' and tag_way1(req_idx) = req_tag) else '0';
    cache_hit <= hit_way0 or hit_way1;

    -- Output instruction multiplexing
    process(cache_hit, hit_way0, hit_way1, req_idx, word_idx, data_way0, data_way1, state_reg)
        variable sel_line : line_t;
    begin
        if state_reg = ST_IDLE and cache_hit = '1' then
            if hit_way0 = '1' then
                sel_line := data_way0(req_idx);
            else
                sel_line := data_way1(req_idx);
            end if;

            fetch_data0  <= sel_line(word_idx);
            fetch_valid0 <= '1';

            if word_idx < 7 then
                fetch_data1  <= sel_line(word_idx + 1);
                fetch_valid1 <= '1';
            else
                -- Crossed cache line boundary: second way invalid for this beat
                fetch_data1  <= (others => '0');
                fetch_valid1 <= '0';
            end if;
            fetch_ready <= '1';
        else
            fetch_data0  <= (others => '0');
            fetch_data1  <= (others => '0');
            fetch_valid0 <= '0';
            fetch_valid1 <= '0';
            fetch_ready  <= '0';
        end if;
    end process;

    -- AXI4 static configuration
    m_axi_arlen   <= x"07"; -- 8 beats (8 x 4 bytes = 32 bytes)
    m_axi_arsize  <= "010"; -- 4 bytes per beat
    m_axi_arburst <= AXI4_BURST_INCR;

    -- Cache Refill Controller FSM
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state_reg     <= ST_IDLE;
            val_way0      <= (others => '0');
            val_way1      <= (others => '0');
            plru_bits     <= (others => '0');
            m_axi_arvalid <= '0';
            m_axi_rready  <= '0';
            m_axi_araddr  <= (others => '0');
            beat_count    <= 0;
            victim_way    <= 0;
        elsif rising_edge(clk) then
            if flush = '1' then
                val_way0  <= (others => '0');
                val_way1  <= (others => '0');
                state_reg <= ST_IDLE;
            else
                case state_reg is
                    when ST_IDLE =>
                        m_axi_arvalid <= '0';
                        m_axi_rready  <= '0';
                        beat_count    <= 0;

                        if fetch_req = '1' and cache_hit = '0' then
                            -- Cache Miss: Trigger line refill
                            m_axi_araddr  <= fetch_addr(ADDR_WIDTH-1 downto 5) & "00000";
                            m_axi_arvalid <= '1';
                            if plru_bits(req_idx) = '0' then
                                victim_way <= 0;
                            else
                                victim_way <= 1;
                            end if;
                            state_reg <= ST_REFILL_ADDR;
                        elsif fetch_req = '1' and cache_hit = '1' then
                            -- Update PLRU on hit
                            if hit_way0 = '1' then
                                plru_bits(req_idx) <= '1';
                            else
                                plru_bits(req_idx) <= '0';
                            end if;
                        end if;

                    when ST_REFILL_ADDR =>
                        if m_axi_arready = '1' then
                            m_axi_arvalid <= '0';
                            m_axi_rready  <= '1';
                            state_reg     <= ST_REFILL_DATA;
                        end if;

                    when ST_REFILL_DATA =>
                        if m_axi_rvalid = '1' then
                            refill_line(beat_count) <= m_axi_rdata;
                            if beat_count = 7 or m_axi_rlast = '1' then
                                m_axi_rready <= '0';
                                state_reg    <= ST_REFILL_DONE;
                            else
                                beat_count <= beat_count + 1;
                            end if;
                        end if;

                    when ST_REFILL_DONE =>
                        -- Write refilled line into cache
                        if victim_way = 0 then
                            data_way0(req_idx) <= refill_line;
                            tag_way0(req_idx)  <= req_tag;
                            val_way0(req_idx)  <= '1';
                            plru_bits(req_idx) <= '1';
                        else
                            data_way1(req_idx) <= refill_line;
                            tag_way1(req_idx)  <= req_tag;
                            val_way1(req_idx)  <= '1';
                            plru_bits(req_idx) <= '0';
                        end if;
                        state_reg <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
