-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Interconnect Package: AXI4-Full and AXI4-Lite Bus Protocol Types
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package talos_axi4_pkg is

    -- -------------------------------------------------------------------------
    -- Protocol Width Parameters
    -- -------------------------------------------------------------------------
    constant AXI4_ID_WIDTH          : integer := 4;
    constant AXI4_ADDR_WIDTH        : integer := 32;
    constant AXI4_DATA_WIDTH        : integer := 32;
    constant AXI4_STRB_WIDTH        : integer := AXI4_DATA_WIDTH / 8;
    constant AXI4_USER_WIDTH        : integer := 1;

    -- -------------------------------------------------------------------------
    -- Burst Type Encoding
    -- -------------------------------------------------------------------------
    constant AXI4_BURST_FIXED       : std_logic_vector(1 downto 0) := "00";
    constant AXI4_BURST_INCR        : std_logic_vector(1 downto 0) := "01";
    constant AXI4_BURST_WRAP        : std_logic_vector(1 downto 0) := "10";

    -- -------------------------------------------------------------------------
    -- Response Encoding
    -- -------------------------------------------------------------------------
    constant AXI4_RESP_OKAY         : std_logic_vector(1 downto 0) := "00";
    constant AXI4_RESP_EXOKAY       : std_logic_vector(1 downto 0) := "01";
    constant AXI4_RESP_SLVERR       : std_logic_vector(1 downto 0) := "10";
    constant AXI4_RESP_DECERR       : std_logic_vector(1 downto 0) := "11";

    -- -------------------------------------------------------------------------
    -- Protection Encoding
    -- -------------------------------------------------------------------------
    constant AXI4_PROT_UNPRIV       : std_logic_vector(2 downto 0) := "000";
    constant AXI4_PROT_PRIV         : std_logic_vector(2 downto 0) := "001";
    constant AXI4_PROT_SECURE       : std_logic_vector(2 downto 0) := "000";
    constant AXI4_PROT_NONSECURE    : std_logic_vector(2 downto 0) := "010";
    constant AXI4_PROT_DATA         : std_logic_vector(2 downto 0) := "000";
    constant AXI4_PROT_INSTRUCTION  : std_logic_vector(2 downto 0) := "100";

    -- -------------------------------------------------------------------------
    -- AXI4-Full Master-to-Slave Signals
    -- -------------------------------------------------------------------------
    type axi4_m2s_t is record
        -- Write Address Channel
        awid     : std_logic_vector(AXI4_ID_WIDTH-1 downto 0);
        awaddr   : std_logic_vector(AXI4_ADDR_WIDTH-1 downto 0);
        awlen    : std_logic_vector(7 downto 0);
        awsize   : std_logic_vector(2 downto 0);
        awburst  : std_logic_vector(1 downto 0);
        awlock   : std_logic;
        awcache  : std_logic_vector(3 downto 0);
        awprot   : std_logic_vector(2 downto 0);
        awqos    : std_logic_vector(3 downto 0);
        awvalid  : std_logic;
        -- Write Data Channel
        wdata    : std_logic_vector(AXI4_DATA_WIDTH-1 downto 0);
        wstrb    : std_logic_vector(AXI4_STRB_WIDTH-1 downto 0);
        wlast    : std_logic;
        wvalid   : std_logic;
        -- Write Response Channel
        bready   : std_logic;
        -- Read Address Channel
        arid     : std_logic_vector(AXI4_ID_WIDTH-1 downto 0);
        araddr   : std_logic_vector(AXI4_ADDR_WIDTH-1 downto 0);
        arlen    : std_logic_vector(7 downto 0);
        arsize   : std_logic_vector(2 downto 0);
        arburst  : std_logic_vector(1 downto 0);
        arlock   : std_logic;
        arcache  : std_logic_vector(3 downto 0);
        arprot   : std_logic_vector(2 downto 0);
        arqos    : std_logic_vector(3 downto 0);
        arvalid  : std_logic;
        -- Read Data Channel
        rready   : std_logic;
    end record axi4_m2s_t;

    -- -------------------------------------------------------------------------
    -- AXI4-Full Slave-to-Master Signals
    -- -------------------------------------------------------------------------
    type axi4_s2m_t is record
        -- Write Address Channel
        awready  : std_logic;
        -- Write Data Channel
        wready   : std_logic;
        -- Write Response Channel
        bid      : std_logic_vector(AXI4_ID_WIDTH-1 downto 0);
        bresp    : std_logic_vector(1 downto 0);
        bvalid   : std_logic;
        -- Read Address Channel
        arready  : std_logic;
        -- Read Data Channel
        rid      : std_logic_vector(AXI4_ID_WIDTH-1 downto 0);
        rdata    : std_logic_vector(AXI4_DATA_WIDTH-1 downto 0);
        rresp    : std_logic_vector(1 downto 0);
        rlast    : std_logic;
        rvalid   : std_logic;
    end record axi4_s2m_t;

    constant AXI4_M2S_INIT : axi4_m2s_t := (
        awid     => (others => '0'),
        awaddr   => (others => '0'),
        awlen    => (others => '0'),
        awsize   => "010",
        awburst  => AXI4_BURST_INCR,
        awlock   => '0',
        awcache  => "0011",
        awprot   => AXI4_PROT_DATA,
        awqos    => (others => '0'),
        awvalid  => '0',
        wdata    => (others => '0'),
        wstrb    => (others => '0'),
        wlast    => '0',
        wvalid   => '0',
        bready   => '0',
        arid     => (others => '0'),
        araddr   => (others => '0'),
        arlen    => (others => '0'),
        arsize   => "010",
        arburst  => AXI4_BURST_INCR,
        arlock   => '0',
        arcache  => "0011",
        arprot   => AXI4_PROT_DATA,
        arqos    => (others => '0'),
        arvalid  => '0',
        rready   => '0'
    );

    constant AXI4_S2M_INIT : axi4_s2m_t := (
        awready  => '0',
        wready   => '0',
        bid      => (others => '0'),
        bresp    => AXI4_RESP_OKAY,
        bvalid   => '0',
        arready  => '0',
        rid      => (others => '0'),
        rdata    => (others => '0'),
        rresp    => AXI4_RESP_OKAY,
        rlast    => '0',
        rvalid   => '0'
    );

    -- -------------------------------------------------------------------------
    -- AXI4-Lite Master-to-Slave Signals
    -- -------------------------------------------------------------------------
    type axil_m2s_t is record
        awaddr   : std_logic_vector(AXI4_ADDR_WIDTH-1 downto 0);
        awprot   : std_logic_vector(2 downto 0);
        awvalid  : std_logic;
        wdata    : std_logic_vector(AXI4_DATA_WIDTH-1 downto 0);
        wstrb    : std_logic_vector(AXI4_STRB_WIDTH-1 downto 0);
        wvalid   : std_logic;
        bready   : std_logic;
        araddr   : std_logic_vector(AXI4_ADDR_WIDTH-1 downto 0);
        arprot   : std_logic_vector(2 downto 0);
        arvalid  : std_logic;
        rready   : std_logic;
    end record axil_m2s_t;

    -- -------------------------------------------------------------------------
    -- AXI4-Lite Slave-to-Master Signals
    -- -------------------------------------------------------------------------
    type axil_s2m_t is record
        awready  : std_logic;
        wready   : std_logic;
        bresp    : std_logic_vector(1 downto 0);
        bvalid   : std_logic;
        arready  : std_logic;
        rdata    : std_logic_vector(AXI4_DATA_WIDTH-1 downto 0);
        rresp    : std_logic_vector(1 downto 0);
        rvalid   : std_logic;
    end record axil_s2m_t;

    constant AXIL_M2S_INIT : axil_m2s_t := (
        awaddr   => (others => '0'),
        awprot   => (others => '0'),
        awvalid  => '0',
        wdata    => (others => '0'),
        wstrb    => (others => '0'),
        wvalid   => '0',
        bready   => '0',
        araddr   => (others => '0'),
        arprot   => (others => '0'),
        arvalid  => '0',
        rready   => '0'
    );

    constant AXIL_S2M_INIT : axil_s2m_t := (
        awready  => '0',
        wready   => '0',
        bresp    => AXI4_RESP_OKAY,
        bvalid   => '0',
        arready  => '0',
        rdata    => (others => '0'),
        rresp    => AXI4_RESP_OKAY,
        rvalid   => '0'
    );

end package talos_axi4_pkg;
