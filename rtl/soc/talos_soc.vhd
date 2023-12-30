-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC: Complete System-on-Chip Top-Level Integration
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_soc is
    generic (
        CLOCK_FREQ      : integer := 50000000; -- 50 MHz default system clock
        BAUD_RATE       : integer := 115200;   -- Standard UART baud rate
        BRAM_ADDR_WIDTH : integer := 16        -- 64KB On-Chip High-Speed RAM
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;

        -- Physical Peripherals
        uart_rx  : in  std_logic;
        uart_tx  : out std_logic;

        -- External Interrupt Inputs
        ext_irq  : in  std_logic;

        -- Status and Diagnostic Outputs
        gpio_out : out std_logic_vector(7 downto 0);
        gpio_in  : in  std_logic_vector(7 downto 0)
    );
end entity talos_soc;

architecture rtl of talos_soc is

    -- CPU Core AXI4 Master Interface
    signal core_axi_m2s : axi4_m2s_t;
    signal core_axi_s2m : axi4_s2m_t;

    -- Crossbar Slave Interfaces
    signal rom_axil_m2s   : axil_m2s_t;
    signal rom_axil_s2m   : axil_s2m_t;

    signal ram_axi_m2s    : axi4_m2s_t;
    signal ram_axi_s2m    : axi4_s2m_t;

    signal uart_axil_m2s  : axil_m2s_t;
    signal uart_axil_s2m  : axil_s2m_t;

    signal timer_axil_m2s : axil_m2s_t;
    signal timer_axil_s2m : axil_s2m_t;

    -- Peripheral Interrupts
    signal timer_irq      : std_logic;

    -- Diagnostic Register
    signal gpio_reg       : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- Diagnostic and Heartbeat Mapping
    gpio_out <= gpio_reg;

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            gpio_reg <= (others => '0');
        elsif rising_edge(clk) then
            gpio_reg(0) <= timer_irq;
            gpio_reg(1) <= core_axi_m2s.arvalid;
            gpio_reg(2) <= core_axi_m2s.awvalid;
            gpio_reg(3) <= core_axi_s2m.rvalid;
            gpio_reg(4) <= core_axi_s2m.bvalid;
            gpio_reg(5) <= uart_axil_m2s.wvalid;
            gpio_reg(7 downto 6) <= gpio_in(1 downto 0);
        end if;
    end process;

    -- 1. Dual-Issue Out-of-Order CPU Core
    u_cpu : entity work.talos_core
        port map (
            clk         => clk,
            rst_n       => rst_n,
            ext_int     => ext_irq,
            timer_int   => timer_irq,
            sw_int      => '0',
            m_axi_m2s   => core_axi_m2s,
            m_axi_s2m   => core_axi_s2m
        );

    -- 2. AXI4 / AXI4-Lite Address Crossbar Interconnect
    u_xbar : entity work.talos_axi4_xbar
        port map (
            clk         => clk,
            rst_n       => rst_n,
            s_axi_m2s   => core_axi_m2s,
            s_axi_s2m   => core_axi_s2m,
            rom_m2s     => rom_axil_m2s,
            rom_s2m     => rom_axil_s2m,
            ram_m2s     => ram_axi_m2s,
            ram_s2m     => ram_axi_s2m,
            uart_m2s    => uart_axil_m2s,
            uart_s2m    => uart_axil_s2m,
            timer_m2s   => timer_axil_m2s,
            timer_s2m   => timer_axil_s2m
        );

    -- 3. Slave Port 0: Non-Volatile Boot ROM
    u_boot_rom : entity work.talos_boot_rom
        port map (
            clk      => clk,
            rst_n    => rst_n,
            s_axil   => rom_axil_m2s,
            s_axil_o => rom_axil_s2m
        );

    -- 4. Slave Port 1: Main High-Speed Synchronous RAM Block
    u_bram : entity work.talos_bram_ctrl
        generic map (
            ADDR_WIDTH => BRAM_ADDR_WIDTH
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            s_axi_m2s => ram_axi_m2s,
            s_axi_s2m => ram_axi_s2m
        );

    -- 5. Slave Port 2: Memory-Mapped UART 16550 Controller
    u_uart : entity work.talos_uart
        generic map (
            CLOCK_FREQ => CLOCK_FREQ,
            BAUD_RATE  => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst_n    => rst_n,
            s_axil   => uart_axil_m2s,
            s_axil_o => uart_axil_s2m,
            tx       => uart_tx,
            rx       => uart_rx
        );

    -- 6. Slave Port 3: Memory-Mapped 64-bit CLINT Timer
    u_timer : entity work.talos_timer
        port map (
            clk       => clk,
            rst_n     => rst_n,
            s_axil    => timer_axil_m2s,
            s_axil_o  => timer_axil_s2m,
            timer_int => timer_irq
        );

end architecture rtl;
