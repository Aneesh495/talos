-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Peripherals: Synchronous Boot ROM with Reset Vector
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_boot_rom is
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;

        -- AXI4-Lite Slave Interface
        s_axil   : in  axil_m2s_t;
        s_axil_o : out axil_s2m_t
    );
end entity talos_boot_rom;

architecture rtl of talos_boot_rom is

    -- Boot code:
    -- 0x1000: auipc x1, 0x80000 -> x1 = 0x80001000
    -- 0x1004: jalr  x0, x1, -0x1000 -> jump to 0x80000000 (Entrypoint in SRAM)
    type rom_array_t is array (0 to 15) of std_logic_vector(31 downto 0);
    constant BOOT_CODE : rom_array_t := (
        0 => x"80000097", -- auipc ra, 0x80000
        1 => x"00008067", -- jr ra
        2 => x"00000013", -- nop
        3 => x"00000013", -- nop
        others => x"00000013"
    );

begin

    process(clk, rst_n)
        variable word_idx : integer range 0 to 15;
    begin
        if rst_n = '0' then
            s_axil_o.arready <= '1';
            s_axil_o.rvalid  <= '0';
            s_axil_o.rdata   <= (others => '0');
            s_axil_o.rresp   <= AXI4_RESP_OKAY;
            s_axil_o.awready <= '0';
            s_axil_o.wready  <= '0';
            s_axil_o.bvalid  <= '0';
            s_axil_o.bresp   <= AXI4_RESP_DECERR;
        elsif rising_edge(clk) then
            if s_axil.arvalid = '1' then
                word_idx := to_integer(unsigned(s_axil.araddr(5 downto 2)));
                s_axil_o.rdata  <= BOOT_CODE(word_idx);
                s_axil_o.rvalid <= '1';
            elsif s_axil.rready = '1' then
                s_axil_o.rvalid <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
