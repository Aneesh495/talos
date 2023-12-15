-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Commit: Privileged Control and Status Register (CSR) Bank (M/U-Mode)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;

entity talos_csr is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        -- Instruction Access from Execution / Commit
        csr_en      : in  std_logic;
        csr_addr    : in  std_logic_vector(11 downto 0);
        csr_wdata   : in  std_logic_vector(XLEN-1 downto 0);
        csr_op      : in  std_logic_vector(1 downto 0); -- 01: Write, 10: Set, 11: Clear
        csr_rdata   : out std_logic_vector(XLEN-1 downto 0);

        -- Hardware Trap Notification
        trap_in_val : in  std_logic;
        trap_in_pc  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        trap_in_cau : in  std_logic_vector(4 downto 0);
        trap_in_tval: in  std_logic_vector(XLEN-1 downto 0);

        -- Trap Return (MRET)
        mret_val    : in  std_logic;
        mret_pc     : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- External Interrupt Inputs
        ext_int     : in  std_logic;
        timer_int   : in  std_logic;
        sw_int      : in  std_logic;

        -- Hardware Outputs to Core
        trap_vector : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        int_pending : out std_logic
    );
end entity talos_csr;

architecture rtl of talos_csr is

    -- Canonical RISC-V Privileged Registers
    signal mstatus_reg  : std_logic_vector(31 downto 0) := x"00001800"; -- MPP = 3 (M-Mode)
    signal misa_reg     : std_logic_vector(31 downto 0) := x"40001124"; -- RV32IMF
    signal mie_reg      : std_logic_vector(31 downto 0) := (others => '0');
    signal mtvec_reg    : std_logic_vector(31 downto 0) := x"00001004";
    signal mscratch_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal mepc_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal mcause_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal mtval_reg    : std_logic_vector(31 downto 0) := (others => '0');
    signal mip_reg      : std_logic_vector(31 downto 0) := (others => '0');

    -- 64-bit Hardware Counters
    signal mcycle_reg   : unsigned(63 downto 0) := (others => '0');
    signal minstret_reg : unsigned(63 downto 0) := (others => '0');

    signal rdata_comb   : std_logic_vector(31 downto 0);

begin

    trap_vector <= mtvec_reg;
    mret_pc     <= mepc_reg;

    -- Interrupt pending when enabled in mstatus and mie
    int_pending <= mstatus_reg(3) and (
        (mie_reg(11) and ext_int) or
        (mie_reg(7)  and timer_int) or
        (mie_reg(3)  and sw_int)
    );

    -- Combinational CSR Read Multiplexer
    process(csr_addr, mstatus_reg, misa_reg, mie_reg, mtvec_reg,
            mscratch_reg, mepc_reg, mcause_reg, mtval_reg, mip_reg,
            mcycle_reg, minstret_reg)
    begin
        case csr_addr is
            when CSR_MSTATUS   => rdata_comb <= mstatus_reg;
            when CSR_MISA      => rdata_comb <= misa_reg;
            when CSR_MIE       => rdata_comb <= mie_reg;
            when CSR_MTVEC     => rdata_comb <= mtvec_reg;
            when CSR_MSCRATCH  => rdata_comb <= mscratch_reg;
            when CSR_MEPC      => rdata_comb <= mepc_reg;
            when CSR_MCAUSE    => rdata_comb <= mcause_reg;
            when CSR_MTVAL     => rdata_comb <= mtval_reg;
            when CSR_MIP       => rdata_comb <= mip_reg;
            when CSR_MCYCLE | CSR_CYCLE =>
                rdata_comb <= std_logic_vector(mcycle_reg(31 downto 0));
            when CSR_MCYCLEH =>
                rdata_comb <= std_logic_vector(mcycle_reg(63 downto 32));
            when CSR_MINSTRET | CSR_INSTRET =>
                rdata_comb <= std_logic_vector(minstret_reg(31 downto 0));
            when CSR_MINSTRETH =>
                rdata_comb <= std_logic_vector(minstret_reg(63 downto 32));
            when CSR_MVENDORID =>
                rdata_comb <= x"00000000";
            when CSR_MARCHID =>
                rdata_comb <= x"00000000";
            when CSR_MIMPID =>
                rdata_comb <= x"00000001";
            when CSR_MHARTID =>
                rdata_comb <= x"00000000";
            when others =>
                rdata_comb <= (others => '0');
        end case;
    end process;

    csr_rdata <= rdata_comb;

    -- CSR Synchronous State Machine
    process(clk, rst_n)
        variable new_val : std_logic_vector(31 downto 0);
    begin
        if rst_n = '0' then
            mstatus_reg  <= x"00001800";
            mie_reg      <= (others => '0');
            mtvec_reg    <= x"00001004";
            mscratch_reg <= (others => '0');
            mepc_reg     <= (others => '0');
            mcause_reg   <= (others => '0');
            mtval_reg    <= (others => '0');
            mip_reg      <= (others => '0');
            mcycle_reg   <= (others => '0');
            minstret_reg <= (others => '0');
        elsif rising_edge(clk) then
            mcycle_reg <= mcycle_reg + 1;

            -- Update interrupt pending bits
            mip_reg(11) <= ext_int;
            mip_reg(7)  <= timer_int;
            mip_reg(3)  <= sw_int;

            -- Handle Hardware Trap Entry
            if trap_in_val = '1' then
                mepc_reg       <= trap_in_pc;
                mcause_reg     <= (31 downto 5 => '0') & trap_in_cau;
                mtval_reg      <= trap_in_tval;
                mstatus_reg(7) <= mstatus_reg(3); -- MPIE <= MIE
                mstatus_reg(3) <= '0';            -- MIE <= 0

            -- Handle MRET Return
            elsif mret_val = '1' then
                mstatus_reg(3) <= mstatus_reg(7); -- MIE <= MPIE
                mstatus_reg(7) <= '1';            -- MPIE <= 1

            -- Handle Normal Software CSR Updates
            elsif csr_en = '1' then
                case csr_op is
                    when "01" => new_val := csr_wdata;                  -- CSRRW
                    when "10" => new_val := rdata_comb or csr_wdata;   -- CSRRS
                    when "11" => new_val := rdata_comb and not csr_wdata;-- CSRRC
                    when others => new_val := rdata_comb;
                end case;

                case csr_addr is
                    when CSR_MSTATUS  => mstatus_reg  <= new_val;
                    when CSR_MIE      => mie_reg      <= new_val;
                    when CSR_MTVEC    => mtvec_reg    <= new_val;
                    when CSR_MSCRATCH => mscratch_reg <= new_val;
                    when CSR_MEPC     => mepc_reg     <= new_val;
                    when CSR_MCAUSE   => mcause_reg   <= new_val;
                    when CSR_MTVAL    => mtval_reg    <= new_val;
                    when others => null;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
