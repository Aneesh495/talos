-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- SoC Peripherals: 64-Bit Machine Timer (MTIME / MTIMECMP)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_timer is
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;

        -- AXI4-Lite Slave Interface
        s_axil    : in  axil_m2s_t;
        s_axil_o  : out axil_s2m_t;

        -- Timer Interrupt Output to Core CSR
        timer_int : out std_logic
    );
end entity talos_timer;

architecture rtl of talos_timer is

    -- 64-bit Counter and Comparator
    signal mtime_reg    : unsigned(63 downto 0) := (others => '0');
    signal mtimecmp_reg : unsigned(63 downto 0) := (others => '1'); -- Max value initially

begin

    -- Interrupt fires whenever mtime >= mtimecmp
    timer_int <= '1' when mtime_reg >= mtimecmp_reg else '0';

    -- Counter advancement and AXI4-Lite Register Interface
    process(clk, rst_n)
        variable addr : std_logic_vector(3 downto 0);
    begin
        if rst_n = '0' then
            mtime_reg        <= (others => '0');
            mtimecmp_reg     <= (others => '1');
            s_axil_o.awready <= '1';
            s_axil_o.wready  <= '1';
            s_axil_o.bvalid  <= '0';
            s_axil_o.bresp   <= AXI4_RESP_OKAY;
            s_axil_o.arready <= '1';
            s_axil_o.rvalid  <= '0';
            s_axil_o.rdata   <= (others => '0');
            s_axil_o.rresp   <= AXI4_RESP_OKAY;
        elsif rising_edge(clk) then
            mtime_reg <= mtime_reg + 1;

            -- Write Transaction
            if s_axil.awvalid = '1' and s_axil.wvalid = '1' then
                addr := s_axil.awaddr(3 downto 0);
                case addr is
                    when x"0" => -- MTIME lower 32
                        mtime_reg(31 downto 0) <= unsigned(s_axil.wdata);
                    when x"4" => -- MTIME upper 32
                        mtime_reg(63 downto 32) <= unsigned(s_axil.wdata);
                    when x"8" => -- MTIMECMP lower 32
                        mtimecmp_reg(31 downto 0) <= unsigned(s_axil.wdata);
                    when x"C" => -- MTIMECMP upper 32
                        mtimecmp_reg(63 downto 32) <= unsigned(s_axil.wdata);
                    when others =>
                        null;
                end case;
                s_axil_o.bvalid <= '1';
            elsif s_axil.bready = '1' then
                s_axil_o.bvalid <= '0';
            end if;

            -- Read Transaction
            if s_axil.arvalid = '1' then
                addr := s_axil.araddr(3 downto 0);
                case addr is
                    when x"0" => s_axil_o.rdata <= std_logic_vector(mtime_reg(31 downto 0));
                    when x"4" => s_axil_o.rdata <= std_logic_vector(mtime_reg(63 downto 32));
                    when x"8" => s_axil_o.rdata <= std_logic_vector(mtimecmp_reg(31 downto 0));
                    when x"C" => s_axil_o.rdata <= std_logic_vector(mtimecmp_reg(63 downto 32));
                    when others => s_axil_o.rdata <= (others => '0');
                end case;
                s_axil_o.rvalid <= '1';
            elsif s_axil.rready = '1' then
                s_axil_o.rvalid <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
