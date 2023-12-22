-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Interconnect: Dual-Channel AXI4 Master Burst Controller
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_axi4_master is
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;

        -- Channel 0: I-Cache Read Refill Port
        icache_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        icache_arlen   : in  std_logic_vector(7 downto 0);
        icache_arsize  : in  std_logic_vector(2 downto 0);
        icache_arburst : in  std_logic_vector(1 downto 0);
        icache_arvalid : in  std_logic;
        icache_arready : out std_logic;

        icache_rdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        icache_rresp   : out std_logic_vector(1 downto 0);
        icache_rlast   : out std_logic;
        icache_rvalid  : out std_logic;
        icache_rready  : in  std_logic;

        -- Channel 1: D-Cache Read Refill Port
        dcache_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        dcache_arlen   : in  std_logic_vector(7 downto 0);
        dcache_arsize  : in  std_logic_vector(2 downto 0);
        dcache_arburst : in  std_logic_vector(1 downto 0);
        dcache_arvalid : in  std_logic;
        dcache_arready : out std_logic;

        dcache_rdata   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        dcache_rresp   : out std_logic_vector(1 downto 0);
        dcache_rlast   : out std_logic;
        dcache_rvalid  : out std_logic;
        dcache_rready  : in  std_logic;

        -- Channel 2: D-Cache Write-Back Port
        dcache_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        dcache_awlen   : in  std_logic_vector(7 downto 0);
        dcache_awsize  : in  std_logic_vector(2 downto 0);
        dcache_awburst : in  std_logic_vector(1 downto 0);
        dcache_awvalid : in  std_logic;
        dcache_awready : out std_logic;

        dcache_wdata   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        dcache_wstrb   : in  std_logic_vector(3 downto 0);
        dcache_wlast   : in  std_logic;
        dcache_wvalid  : in  std_logic;
        dcache_wready  : out std_logic;

        dcache_bvalid  : out std_logic;
        dcache_bready  : in  std_logic;

        -- Unified External AXI4 Master Interface
        m_axi_m2s      : out axi4_m2s_t;
        m_axi_s2m      : in  axi4_s2m_t
    );
end entity talos_axi4_master;

architecture rtl of talos_axi4_master is

    type rd_arb_state_t is (RD_IDLE, RD_BURST_DCACHE, RD_BURST_ICACHE);
    signal rd_state : rd_arb_state_t := RD_IDLE;

    signal m2s_reg  : axi4_m2s_t := AXI4_M2S_INIT;

begin

    m_axi_m2s <= m2s_reg;

    -- Read Address and Data Channel Arbitration (D-Cache has priority over I-Cache)
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_state              <= RD_IDLE;
            m2s_reg.arvalid       <= '0';
            m2s_reg.araddr        <= (others => '0');
            m2s_reg.arlen         <= (others => '0');
            m2s_reg.arsize        <= "010";
            m2s_reg.arburst       <= AXI4_BURST_INCR;
            m2s_reg.arid          <= (others => '0');
            m2s_reg.rready        <= '0';
            dcache_arready        <= '0';
            icache_arready        <= '0';
            dcache_rvalid         <= '0';
            dcache_rdata          <= (others => '0');
            dcache_rresp          <= (others => '0');
            dcache_rlast          <= '0';
            icache_rvalid         <= '0';
            icache_rdata          <= (others => '0');
            icache_rresp          <= (others => '0');
            icache_rlast          <= '0';
        elsif rising_edge(clk) then
            dcache_rvalid  <= '0';
            icache_rvalid  <= '0';
            dcache_arready <= '0';
            icache_arready <= '0';

            case rd_state is
                when RD_IDLE =>
                    m2s_reg.arvalid <= '0';
                    m2s_reg.rready  <= '0';

                    if dcache_arvalid = '1' then
                        -- Service D-Cache miss first
                        m2s_reg.arid    <= "0001";
                        m2s_reg.araddr  <= dcache_araddr;
                        m2s_reg.arlen   <= dcache_arlen;
                        m2s_reg.arsize  <= dcache_arsize;
                        m2s_reg.arburst <= dcache_arburst;
                        m2s_reg.arvalid <= '1';
                        if m_axi_s2m.arready = '1' then
                            dcache_arready  <= '1';
                            m2s_reg.rready  <= '1';
                            rd_state        <= RD_BURST_DCACHE;
                        end if;
                    elsif icache_arvalid = '1' then
                        -- Service I-Cache miss
                        m2s_reg.arid    <= "0000";
                        m2s_reg.araddr  <= icache_araddr;
                        m2s_reg.arlen   <= icache_arlen;
                        m2s_reg.arsize  <= icache_arsize;
                        m2s_reg.arburst <= icache_arburst;
                        m2s_reg.arvalid <= '1';
                        if m_axi_s2m.arready = '1' then
                            icache_arready  <= '1';
                            m2s_reg.rready  <= '1';
                            rd_state        <= RD_BURST_ICACHE;
                        end if;
                    end if;

                when RD_BURST_DCACHE =>
                    m2s_reg.arvalid <= '0';
                    m2s_reg.rready  <= dcache_rready;
                    if m_axi_s2m.rvalid = '1' then
                        dcache_rvalid <= '1';
                        dcache_rdata  <= m_axi_s2m.rdata;
                        dcache_rresp  <= m_axi_s2m.rresp;
                        dcache_rlast  <= m_axi_s2m.rlast;
                        if m_axi_s2m.rlast = '1' then
                            rd_state <= RD_IDLE;
                        end if;
                    end if;

                when RD_BURST_ICACHE =>
                    m2s_reg.arvalid <= '0';
                    m2s_reg.rready  <= icache_rready;
                    if m_axi_s2m.rvalid = '1' then
                        icache_rvalid <= '1';
                        icache_rdata  <= m_axi_s2m.rdata;
                        icache_rresp  <= m_axi_s2m.rresp;
                        icache_rlast  <= m_axi_s2m.rlast;
                        if m_axi_s2m.rlast = '1' then
                            rd_state <= RD_IDLE;
                        end if;
                    end if;

            end case;
        end if;
    end process;

    -- Write Channel Passthrough for D-Cache Evictions
    m2s_reg.awid    <= "0010";
    m2s_reg.awaddr  <= dcache_awaddr;
    m2s_reg.awlen   <= dcache_awlen;
    m2s_reg.awsize  <= dcache_awsize;
    m2s_reg.awburst <= dcache_awburst;
    m2s_reg.awvalid <= dcache_awvalid;
    dcache_awready  <= m_axi_s2m.awready;

    m2s_reg.wdata   <= dcache_wdata;
    m2s_reg.wstrb   <= dcache_wstrb;
    m2s_reg.wlast   <= dcache_wlast;
    m2s_reg.wvalid  <= dcache_wvalid;
    dcache_wready   <= m_axi_s2m.wready;

    m2s_reg.bready  <= dcache_bready;
    dcache_bvalid   <= m_axi_s2m.bvalid;

end architecture rtl;
