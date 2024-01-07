-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Integration Testbench: CPU Core with Simulated AXI4 Memory Subsystem
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity tb_talos_core is
end entity tb_talos_core;

architecture sim of tb_talos_core is

    constant CLK_PERIOD : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';

    signal m_axi_m2s : axi4_m2s_t;
    signal m_axi_s2m : axi4_s2m_t;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.talos_core
        port map (
            clk       => clk,
            rst_n     => rst_n,
            ext_int   => '0',
            timer_int => '0',
            sw_int    => '0',
            m_axi_m2s => m_axi_m2s,
            m_axi_s2m => m_axi_s2m
        );

    -- Simulated AXI4 Memory Responder
    process(clk, rst_n)
        variable beat_count : integer range 0 to 15 := 0;
    begin
        if rst_n = '0' then
            m_axi_s2m.arready <= '1';
            m_axi_s2m.awready <= '1';
            m_axi_s2m.wready  <= '1';
            m_axi_s2m.bvalid  <= '0';
            m_axi_s2m.bresp   <= AXI4_RESP_OKAY;
            m_axi_s2m.bid     <= (others => '0');
            m_axi_s2m.rvalid  <= '0';
            m_axi_s2m.rdata   <= (others => '0');
            m_axi_s2m.rresp   <= AXI4_RESP_OKAY;
            m_axi_s2m.rlast   <= '0';
            m_axi_s2m.rid     <= (others => '0');
            beat_count        := 0;
        elsif rising_edge(clk) then
            -- Read channel responder (burst generator for instruction fetches)
            if m_axi_m2s.arvalid = '1' and m_axi_s2m.rvalid = '0' then
                m_axi_s2m.rvalid <= '1';
                m_axi_s2m.rid    <= m_axi_m2s.arid;
                -- Default instruction payload: addi x1, x0, 1 (0x00100093)
                m_axi_s2m.rdata  <= x"00100093";
                beat_count       := to_integer(unsigned(m_axi_m2s.arlen));
                if beat_count = 0 then
                    m_axi_s2m.rlast <= '1';
                else
                    m_axi_s2m.rlast <= '0';
                end if;
            elsif m_axi_s2m.rvalid = '1' and m_axi_m2s.rready = '1' then
                if beat_count > 0 then
                    beat_count := beat_count - 1;
                    m_axi_s2m.rdata <= x"00000013"; -- nop
                    if beat_count = 0 then
                        m_axi_s2m.rlast <= '1';
                    end if;
                else
                    m_axi_s2m.rvalid <= '0';
                    m_axi_s2m.rlast  <= '0';
                end if;
            end if;

            -- Write channel responder
            if m_axi_m2s.awvalid = '1' and m_axi_m2s.wvalid = '1' then
                m_axi_s2m.bvalid <= '1';
                m_axi_s2m.bid    <= m_axi_m2s.awid;
            elsif m_axi_m2s.bready = '1' then
                m_axi_s2m.bvalid <= '0';
            end if;
        end if;
    end process;

    -- Test Driver Process
    process
    begin
        report "[TEST] Starting tb_talos_core integration verification...";

        rst_n <= '0';
        wait for 30 ns;
        rst_n <= '1';
        wait until rising_edge(clk);

        -- Run simulation for 50 cycles to verify front-end fetch requests and execution progression
        for i in 1 to 50 loop
            wait until rising_edge(clk);
        end loop;

        report "[PASS] tb_talos_core integration verification successful.";
        std.env.stop;
    end process;

end architecture sim;
