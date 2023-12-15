-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Commit: Trap and Interrupt Priority Resolution Controller
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;

entity talos_trap_ctrl is
    port (
        -- ROB Synchronous Exception Inputs
        rob_trap_val        : in  std_logic;
        rob_trap_cause      : in  std_logic_vector(4 downto 0);
        rob_trap_pc         : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- CSR Interrupt Inputs
        csr_int_pending     : in  std_logic;
        ext_int             : in  std_logic;
        timer_int           : in  std_logic;
        sw_int              : in  std_logic;

        -- Resolved Trap / Interrupt Outputs to CSR & Front-End
        trap_fire_val       : out std_logic;
        trap_fire_pc        : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        trap_fire_cause     : out std_logic_vector(4 downto 0);
        trap_fire_tval      : out std_logic_vector(XLEN-1 downto 0);
        is_interrupt        : out std_logic
    );
end entity talos_trap_ctrl;

architecture rtl of talos_trap_ctrl is
begin

    process(rob_trap_val, rob_trap_cause, rob_trap_pc,
            csr_int_pending, ext_int, timer_int, sw_int)
    begin
        if csr_int_pending = '1' then
            -- Asynchronous Interrupt (takes priority between instruction retirements)
            trap_fire_val   <= '1';
            trap_fire_pc    <= rob_trap_pc;
            trap_fire_tval  <= (others => '0');
            is_interrupt    <= '1';

            if ext_int = '1' then
                trap_fire_cause <= '1' & INT_CAUSE_M_EXTERNAL;
            elsif sw_int = '1' then
                trap_fire_cause <= '1' & INT_CAUSE_M_SOFTWARE;
            else
                trap_fire_cause <= '1' & INT_CAUSE_M_TIMER;
            end if;

        elsif rob_trap_val = '1' then
            -- Synchronous Exception from ROB Head
            trap_fire_val   <= '1';
            trap_fire_pc    <= rob_trap_pc;
            trap_fire_cause <= rob_trap_cause;
            trap_fire_tval  <= rob_trap_pc;
            is_interrupt    <= '0';
        else
            trap_fire_val   <= '0';
            trap_fire_pc    <= (others => '0');
            trap_fire_cause <= (others => '0');
            trap_fire_tval  <= (others => '0');
            is_interrupt    <= '0';
        end if;
    end process;

end architecture rtl;
