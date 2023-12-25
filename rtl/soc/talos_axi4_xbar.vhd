-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Interconnect: Memory Map Crossbar and Slave Route Demultiplexer
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_axi4_xbar is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        -- Ingress Master from CPU Core
        s_axi_m2s   : in  axi4_m2s_t;
        s_axi_s2m   : out axi4_s2m_t;

        -- Slave Port 0: Boot ROM (0x0000_1000)
        rom_m2s     : out axil_m2s_t;
        rom_s2m     : in  axil_s2m_t;

        -- Slave Port 1: Main SRAM Memory (0x8000_0000)
        ram_m2s     : out axi4_m2s_t;
        ram_s2m     : in  axi4_s2m_t;

        -- Slave Port 2: UART (0x1000_0000)
        uart_m2s    : out axil_m2s_t;
        uart_s2m    : in  axil_s2m_t;

        -- Slave Port 3: Timer (0x1100_0000)
        timer_m2s   : out axil_m2s_t;
        timer_s2m   : in  axil_s2m_t
    );
end entity talos_axi4_xbar;

architecture rtl of talos_axi4_xbar is

    type slave_sel_t is (SEL_NONE, SEL_ROM, SEL_RAM, SEL_UART, SEL_TIMER);
    signal ar_sel : slave_sel_t;
    signal aw_sel : slave_sel_t;

    signal ar_sel_reg : slave_sel_t := SEL_NONE;

begin

    -- Decode Read Address
    process(s_axi_m2s.araddr)
    begin
        if s_axi_m2s.araddr(31 downto 28) = x"8" then
            ar_sel <= SEL_RAM;
        elsif s_axi_m2s.araddr(31 downto 16) = x"0000" and unsigned(s_axi_m2s.araddr(15 downto 12)) <= 1 then
            ar_sel <= SEL_ROM;
        elsif s_axi_m2s.araddr(31 downto 24) = x"10" then
            ar_sel <= SEL_UART;
        elsif s_axi_m2s.araddr(31 downto 24) = x"11" then
            ar_sel <= SEL_TIMER;
        else
            ar_sel <= SEL_RAM; -- Default fallback
        end if;
    end process;

    -- Decode Write Address
    process(s_axi_m2s.awaddr)
    begin
        if s_axi_m2s.awaddr(31 downto 28) = x"8" then
            aw_sel <= SEL_RAM;
        elsif s_axi_m2s.awaddr(31 downto 24) = x"10" then
            aw_sel <= SEL_UART;
        elsif s_axi_m2s.awaddr(31 downto 24) = x"11" then
            aw_sel <= SEL_TIMER;
        else
            aw_sel <= SEL_RAM;
        end if;
    end process;

    -- Latch active read slave on AR handshake
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            ar_sel_reg <= SEL_NONE;
        elsif rising_edge(clk) then
            if s_axi_m2s.arvalid = '1' and s_axi_s2m.arready = '1' then
                ar_sel_reg <= ar_sel;
            end if;
        end if;
    end process;

    -- Drive RAM Port (Full AXI4)
    ram_m2s.awid    <= s_axi_m2s.awid;
    ram_m2s.awaddr  <= s_axi_m2s.awaddr;
    ram_m2s.awlen   <= s_axi_m2s.awlen;
    ram_m2s.awsize  <= s_axi_m2s.awsize;
    ram_m2s.awburst <= s_axi_m2s.awburst;
    ram_m2s.awlock  <= s_axi_m2s.awlock;
    ram_m2s.awcache <= s_axi_m2s.awcache;
    ram_m2s.awprot  <= s_axi_m2s.awprot;
    ram_m2s.awqos   <= s_axi_m2s.awqos;
    ram_m2s.awvalid <= s_axi_m2s.awvalid when aw_sel = SEL_RAM else '0';

    ram_m2s.wdata   <= s_axi_m2s.wdata;
    ram_m2s.wstrb   <= s_axi_m2s.wstrb;
    ram_m2s.wlast   <= s_axi_m2s.wlast;
    ram_m2s.wvalid  <= s_axi_m2s.wvalid when aw_sel = SEL_RAM else '0';
    ram_m2s.bready  <= s_axi_m2s.bready;

    ram_m2s.arid    <= s_axi_m2s.arid;
    ram_m2s.araddr  <= s_axi_m2s.araddr;
    ram_m2s.arlen   <= s_axi_m2s.arlen;
    ram_m2s.arsize  <= s_axi_m2s.arsize;
    ram_m2s.arburst <= s_axi_m2s.arburst;
    ram_m2s.arlock  <= s_axi_m2s.arlock;
    ram_m2s.arcache <= s_axi_m2s.arcache;
    ram_m2s.arprot  <= s_axi_m2s.arprot;
    ram_m2s.arqos   <= s_axi_m2s.arqos;
    ram_m2s.arvalid <= s_axi_m2s.arvalid when ar_sel = SEL_RAM else '0';
    ram_m2s.rready  <= s_axi_m2s.rready;

    -- Drive ROM Port (AXI4-Lite)
    rom_m2s.araddr  <= s_axi_m2s.araddr;
    rom_m2s.arprot  <= s_axi_m2s.arprot;
    rom_m2s.arvalid <= s_axi_m2s.arvalid when ar_sel = SEL_ROM else '0';
    rom_m2s.rready  <= s_axi_m2s.rready;
    rom_m2s.awaddr  <= (others => '0');
    rom_m2s.awprot  <= (others => '0');
    rom_m2s.awvalid <= '0';
    rom_m2s.wdata   <= (others => '0');
    rom_m2s.wstrb   <= (others => '0');
    rom_m2s.wvalid  <= '0';
    rom_m2s.bready  <= '0';

    -- Drive UART Port (AXI4-Lite)
    uart_m2s.araddr  <= s_axi_m2s.araddr;
    uart_m2s.arprot  <= s_axi_m2s.arprot;
    uart_m2s.arvalid <= s_axi_m2s.arvalid when ar_sel = SEL_UART else '0';
    uart_m2s.rready  <= s_axi_m2s.rready;

    uart_m2s.awaddr  <= s_axi_m2s.awaddr;
    uart_m2s.awprot  <= s_axi_m2s.awprot;
    uart_m2s.awvalid <= s_axi_m2s.awvalid when aw_sel = SEL_UART else '0';
    uart_m2s.wdata   <= s_axi_m2s.wdata;
    uart_m2s.wstrb   <= s_axi_m2s.wstrb;
    uart_m2s.wvalid  <= s_axi_m2s.wvalid when aw_sel = SEL_UART else '0';
    uart_m2s.bready  <= s_axi_m2s.bready;

    -- Drive Timer Port (AXI4-Lite)
    timer_m2s.araddr  <= s_axi_m2s.araddr;
    timer_m2s.arprot  <= s_axi_m2s.arprot;
    timer_m2s.arvalid <= s_axi_m2s.arvalid when ar_sel = SEL_TIMER else '0';
    timer_m2s.rready  <= s_axi_m2s.rready;

    timer_m2s.awaddr  <= s_axi_m2s.awaddr;
    timer_m2s.awprot  <= s_axi_m2s.awprot;
    timer_m2s.awvalid <= s_axi_m2s.awvalid when aw_sel = SEL_TIMER else '0';
    timer_m2s.wdata   <= s_axi_m2s.wdata;
    timer_m2s.wstrb   <= s_axi_m2s.wstrb;
    timer_m2s.wvalid  <= s_axi_m2s.wvalid when aw_sel = SEL_TIMER else '0';
    timer_m2s.bready  <= s_axi_m2s.bready;

    -- Multiplex Responses back to CPU Core Master
    process(ar_sel, ar_sel_reg, aw_sel, ram_s2m, rom_s2m, uart_s2m, timer_s2m)
        variable cur_r_sel : slave_sel_t;
    begin
        -- Address Ready
        case ar_sel is
            when SEL_RAM   => s_axi_s2m.arready <= ram_s2m.arready;
            when SEL_ROM   => s_axi_s2m.arready <= rom_s2m.arready;
            when SEL_UART  => s_axi_s2m.arready <= uart_s2m.arready;
            when SEL_TIMER => s_axi_s2m.arready <= timer_s2m.arready;
            when others    => s_axi_s2m.arready <= '0';
        end case;

        case aw_sel is
            when SEL_RAM   => s_axi_s2m.awready <= ram_s2m.awready;
                              s_axi_s2m.wready  <= ram_s2m.wready;
                              s_axi_s2m.bid     <= ram_s2m.bid;
                              s_axi_s2m.bresp   <= ram_s2m.bresp;
                              s_axi_s2m.bvalid  <= ram_s2m.bvalid;
            when SEL_UART  => s_axi_s2m.awready <= uart_s2m.awready;
                              s_axi_s2m.wready  <= uart_s2m.wready;
                              s_axi_s2m.bid     <= (others => '0');
                              s_axi_s2m.bresp   <= uart_s2m.bresp;
                              s_axi_s2m.bvalid  <= uart_s2m.bvalid;
            when SEL_TIMER => s_axi_s2m.awready <= timer_s2m.awready;
                              s_axi_s2m.wready  <= timer_s2m.wready;
                              s_axi_s2m.bid     <= (others => '0');
                              s_axi_s2m.bresp   <= timer_s2m.bresp;
                              s_axi_s2m.bvalid  <= timer_s2m.bvalid;
            when others    => s_axi_s2m.awready <= '0';
                              s_axi_s2m.wready  <= '0';
                              s_axi_s2m.bid     <= (others => '0');
                              s_axi_s2m.bresp   <= AXI4_RESP_DECERR;
                              s_axi_s2m.bvalid  <= '0';
        end case;

        -- Read Data Multiplexing
        if ar_sel_reg /= SEL_NONE then
            cur_r_sel := ar_sel_reg;
        else
            cur_r_sel := ar_sel;
        end if;

        case cur_r_sel is
            when SEL_RAM =>
                s_axi_s2m.rid    <= ram_s2m.rid;
                s_axi_s2m.rdata  <= ram_s2m.rdata;
                s_axi_s2m.rresp  <= ram_s2m.rresp;
                s_axi_s2m.rlast  <= ram_s2m.rlast;
                s_axi_s2m.rvalid <= ram_s2m.rvalid;
            when SEL_ROM =>
                s_axi_s2m.rid    <= (others => '0');
                s_axi_s2m.rdata  <= rom_s2m.rdata;
                s_axi_s2m.rresp  <= rom_s2m.rresp;
                s_axi_s2m.rlast  <= '1';
                s_axi_s2m.rvalid <= rom_s2m.rvalid;
            when SEL_UART =>
                s_axi_s2m.rid    <= (others => '0');
                s_axi_s2m.rdata  <= uart_s2m.rdata;
                s_axi_s2m.rresp  <= uart_s2m.rresp;
                s_axi_s2m.rlast  <= '1';
                s_axi_s2m.rvalid <= uart_s2m.rvalid;
            when SEL_TIMER =>
                s_axi_s2m.rid    <= (others => '0');
                s_axi_s2m.rdata  <= timer_s2m.rdata;
                s_axi_s2m.rresp  <= timer_s2m.rresp;
                s_axi_s2m.rlast  <= '1';
                s_axi_s2m.rvalid <= timer_s2m.rvalid;
            when others =>
                s_axi_s2m.rid    <= (others => '0');
                s_axi_s2m.rdata  <= (others => '0');
                s_axi_s2m.rresp  <= AXI4_RESP_DECERR;
                s_axi_s2m.rlast  <= '1';
                s_axi_s2m.rvalid <= '0';
        end case;
    end process;

end architecture rtl;
