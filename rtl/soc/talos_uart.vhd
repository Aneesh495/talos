-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Peripherals: 16550-Compatible UART Controller with AXI4-Lite Interface
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_uart is
    generic (
        CLOCK_FREQ : integer := 50000000; -- 50 MHz
        BAUD_RATE  : integer := 115200
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;

        -- AXI4-Lite Slave Interface
        s_axil    : in  axil_m2s_t;
        s_axil_o  : out axil_s2m_t;

        -- Physical Serial Lines
        tx        : out std_logic;
        rx        : in  std_logic
    );
end entity talos_uart;

architecture rtl of talos_uart is

    constant CLKS_PER_BIT : integer := CLOCK_FREQ / BAUD_RATE;

    -- TX Serializer signals
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_STOP);
    signal tx_state : tx_state_t := TX_IDLE;

    signal tx_clk_cnt : integer range 0 to CLKS_PER_BIT := 0;
    signal tx_bit_idx : integer range 0 to 7 := 0;
    signal tx_shift   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy    : std_logic := '0';

    -- Transmit Data Buffer
    signal tx_byte_val : std_logic := '0';
    signal tx_byte_dat : std_logic_vector(7 downto 0) := (others => '0');

    -- Line Status Register (LSR)
    -- Bit 5: Transmitter Empty (1 = ready to accept new byte)
    -- Bit 0: Receiver Data Ready
    signal lsr_reg : std_logic_vector(7 downto 0);

begin

    lsr_reg <= "01100000" when tx_busy = '0' else "00000000";

    -- AXI4-Lite Register Interface
    process(clk, rst_n)
        variable addr : std_logic_vector(3 downto 0);
    begin
        if rst_n = '0' then
            s_axil_o.awready <= '1';
            s_axil_o.wready  <= '1';
            s_axil_o.bvalid  <= '0';
            s_axil_o.bresp   <= AXI4_RESP_OKAY;
            s_axil_o.arready <= '1';
            s_axil_o.rvalid  <= '0';
            s_axil_o.rdata   <= (others => '0');
            s_axil_o.rresp   <= AXI4_RESP_OKAY;
            tx_byte_val      <= '0';
            tx_byte_dat      <= (others => '0');
        elsif rising_edge(clk) then
            tx_byte_val <= '0';

            -- Write Handshake
            if s_axil.awvalid = '1' and s_axil.wvalid = '1' then
                addr := s_axil.awaddr(3 downto 0);
                if addr = x"0" then
                    -- Write to Transmit Holding Register (THR)
                    tx_byte_dat <= s_axil.wdata(7 downto 0);
                    tx_byte_val <= '1';
                end if;
                s_axil_o.bvalid <= '1';
            elsif s_axil.bready = '1' then
                s_axil_o.bvalid <= '0';
            end if;

            -- Read Handshake
            if s_axil.arvalid = '1' then
                addr := s_axil.araddr(3 downto 0);
                if addr = x"5" then
                    -- Read Line Status Register (LSR)
                    s_axil_o.rdata <= (31 downto 8 => '0') & lsr_reg;
                elsif addr = x"0" then
                    -- Read Receiver Buffer Register (RBR)
                    s_axil_o.rdata <= (31 downto 8 => '0') & x"00";
                else
                    s_axil_o.rdata <= (others => '0');
                end if;
                s_axil_o.rvalid <= '1';
            elsif s_axil.rready = '1' then
                s_axil_o.rvalid <= '0';
            end if;
        end if;
    end process;

    -- TX Serializer FSM
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state   <= TX_IDLE;
            tx         <= '1';
            tx_busy    <= '0';
            tx_clk_cnt <= 0;
            tx_bit_idx <= 0;
            tx_shift   <= (others => '0');
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    tx <= '1';
                    if tx_byte_val = '1' then
                        tx_shift   <= tx_byte_dat;
                        tx_busy    <= '1';
                        tx_clk_cnt <= 0;
                        tx_state   <= TX_START;
                    else
                        tx_busy <= '0';
                    end if;

                when TX_START =>
                    tx <= '0'; -- Start bit
                    if tx_clk_cnt = CLKS_PER_BIT - 1 then
                        tx_clk_cnt <= 0;
                        tx_bit_idx <= 0;
                        tx_state   <= TX_DATA;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;

                when TX_DATA =>
                    tx <= tx_shift(tx_bit_idx);
                    if tx_clk_cnt = CLKS_PER_BIT - 1 then
                        tx_clk_cnt <= 0;
                        if tx_bit_idx = 7 then
                            tx_state <= TX_STOP;
                        else
                            tx_bit_idx <= tx_bit_idx + 1;
                        end if;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;

                when TX_STOP =>
                    tx <= '1'; -- Stop bit
                    if tx_clk_cnt = CLKS_PER_BIT - 1 then
                        tx_clk_cnt <= 0;
                        tx_state   <= TX_IDLE;
                    else
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
