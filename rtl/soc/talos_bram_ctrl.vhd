-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Peripherals: AXI4-to-SRAM Block RAM Controller
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_bram_ctrl is
    generic (
        ADDR_WIDTH : integer := 14 -- 16KB default on-chip BRAM (16384 bytes = 4096 words)
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;

        -- AXI4 Slave Interface
        s_axi_m2s : in  axi4_m2s_t;
        s_axi_s2m : out axi4_s2m_t
    );
end entity talos_bram_ctrl;

architecture rtl of talos_bram_ctrl is

    type rd_state_t is (RD_IDLE, RD_BURST);
    signal rd_state : rd_state_t := RD_IDLE;

    signal cur_raddr  : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal beats_left : integer range 0 to 255 := 0;

    signal ram_en   : std_logic;
    signal ram_we   : std_logic_vector(3 downto 0);
    signal ram_addr : std_logic_vector(ADDR_WIDTH-3 downto 0);
    signal ram_di   : std_logic_vector(31 downto 0);
    signal ram_do   : std_logic_vector(31 downto 0);

begin

    -- Instantiate Core Synchronous RAM Block
    u_ram : entity work.talos_ram_sp
        generic map (
            DATA_WIDTH => 32,
            ADDR_WIDTH => ADDR_WIDTH - 2,
            BYTE_SIZE  => 8
        )
        port map (
            clk  => clk,
            en   => ram_en,
            we   => ram_we,
            addr => ram_addr,
            di   => ram_di,
            do   => ram_do
        );

    -- Memory Multiplexing (Writes take priority over background reads)
    process(s_axi_m2s, cur_raddr, rd_state)
    begin
        if s_axi_m2s.awvalid = '1' and s_axi_m2s.wvalid = '1' then
            ram_en   <= '1';
            ram_we   <= s_axi_m2s.wstrb;
            ram_addr <= s_axi_m2s.awaddr(ADDR_WIDTH-1 downto 2);
            ram_di   <= s_axi_m2s.wdata;
        elsif rd_state = RD_BURST or s_axi_m2s.arvalid = '1' then
            ram_en   <= '1';
            ram_we   <= "0000";
            if rd_state = RD_BURST then
                ram_addr <= std_logic_vector(cur_raddr(ADDR_WIDTH-1 downto 2));
            else
                ram_addr <= s_axi_m2s.araddr(ADDR_WIDTH-1 downto 2);
            end if;
            ram_di   <= (others => '0');
        else
            ram_en   <= '0';
            ram_we   <= "0000";
            ram_addr <= (others => '0');
            ram_di   <= (others => '0');
        end if;
    end process;

    -- Write Channel Handshakes
    s_axi_s2m.awready <= '1';
    s_axi_s2m.wready  <= '1';
    s_axi_s2m.bid     <= s_axi_m2s.awid;
    s_axi_s2m.bresp   <= AXI4_RESP_OKAY;

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            s_axi_s2m.bvalid <= '0';
        elsif rising_edge(clk) then
            if s_axi_m2s.awvalid = '1' and s_axi_m2s.wvalid = '1' then
                s_axi_s2m.bvalid <= '1';
            elsif s_axi_m2s.bready = '1' then
                s_axi_s2m.bvalid <= '0';
            end if;
        end if;
    end process;

    -- Read Channel Handshake and Burst Control
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_state          <= RD_IDLE;
            s_axi_s2m.arready <= '1';
            s_axi_s2m.rvalid  <= '0';
            s_axi_s2m.rdata   <= (others => '0');
            s_axi_s2m.rresp   <= AXI4_RESP_OKAY;
            s_axi_s2m.rlast   <= '0';
            s_axi_s2m.rid     <= (others => '0');
            cur_raddr         <= (others => '0');
            beats_left        <= 0;
        elsif rising_edge(clk) then
            case rd_state is
                when RD_IDLE =>
                    s_axi_s2m.rvalid <= '0';
                    s_axi_s2m.rlast  <= '0';

                    if s_axi_m2s.arvalid = '1' then
                        s_axi_s2m.arready <= '0';
                        s_axi_s2m.rid     <= s_axi_m2s.arid;
                        cur_raddr         <= unsigned(s_axi_m2s.araddr(ADDR_WIDTH-1 downto 0));
                        beats_left        <= to_integer(unsigned(s_axi_m2s.arlen));
                        rd_state          <= RD_BURST;
                    else
                        s_axi_s2m.arready <= '1';
                    end if;

                when RD_BURST =>
                    s_axi_s2m.rvalid <= '1';
                    s_axi_s2m.rdata  <= ram_do;
                    s_axi_s2m.rresp  <= AXI4_RESP_OKAY;

                    if beats_left = 0 then
                        s_axi_s2m.rlast <= '1';
                    else
                        s_axi_s2m.rlast <= '0';
                    end if;

                    if s_axi_m2s.rready = '1' then
                        if beats_left = 0 then
                            s_axi_s2m.rvalid  <= '0';
                            s_axi_s2m.rlast   <= '0';
                            s_axi_s2m.arready <= '1';
                            rd_state          <= RD_IDLE;
                        else
                            cur_raddr  <= cur_raddr + 4;
                            beats_left <= beats_left - 1;
                        end if;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
