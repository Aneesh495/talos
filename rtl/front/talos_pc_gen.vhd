-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: Program Counter Generator and Multi-Source Redirect Arbiter
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_pc_gen is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        stall               : in  std_logic;

        -- Priority 1: Trap, Interrupt, or MRET redirect from Commit / CSR
        trap_redirect_valid : in  std_logic;
        trap_redirect_pc    : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Priority 2: Speculative branch misprediction recovery from Execution
        branch_mispred_valid: in  std_logic;
        branch_mispred_pc   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Priority 3: Speculative prediction from Branch Predictor / BTB
        pred_taken          : in  std_logic;
        pred_target_pc      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Current Fetch Program Counter
        fetch_pc            : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        fetch_pc_next       : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        pc_redirected       : out std_logic
    );
end entity talos_pc_gen;

architecture rtl of talos_pc_gen is

    constant RESET_VECTOR : std_logic_vector(ADDR_WIDTH-1 downto 0) := x"00001000";

    signal pc_reg       : std_logic_vector(ADDR_WIDTH-1 downto 0) := RESET_VECTOR;
    signal next_pc      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal redirected_i : std_logic;

begin

    -- Priority arbitration logic for next PC calculation
    process(pc_reg, stall, trap_redirect_valid, trap_redirect_pc,
            branch_mispred_valid, branch_mispred_pc,
            pred_taken, pred_target_pc)
        variable seq_pc : unsigned(ADDR_WIDTH-1 downto 0);
    begin
        seq_pc := unsigned(pc_reg) + 8; -- Dual-issue fetch advances by 8 bytes (two 32b words)

        if trap_redirect_valid = '1' then
            next_pc      <= trap_redirect_pc;
            redirected_i <= '1';
        elsif branch_mispred_valid = '1' then
            next_pc      <= branch_mispred_pc;
            redirected_i <= '1';
        elsif stall = '1' then
            next_pc      <= pc_reg;
            redirected_i <= '0';
        elsif pred_taken = '1' then
            next_pc      <= pred_target_pc;
            redirected_i <= '1';
        else
            next_pc      <= std_logic_vector(seq_pc);
            redirected_i <= '0';
        end if;
    end process;

    fetch_pc      <= pc_reg;
    fetch_pc_next <= next_pc;
    pc_redirected <= redirected_i;

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            pc_reg <= RESET_VECTOR;
        elsif rising_edge(clk) then
            pc_reg <= next_pc;
        end if;
    end process;

end architecture rtl;
