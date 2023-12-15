-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Commit: Top-Level Integration (ROB, CSR Bank, Trap Controller)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_commit_top is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        flush               : in  std_logic;

        -- Allocation Interface from Dispatch
        alloc_val0          : in  std_logic;
        alloc_pc0           : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        alloc_rd_arch0      : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        alloc_rd_phys0      : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_old_phys0     : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_has_dest0     : in  std_logic;
        alloc_is_store0     : in  std_logic;
        alloc_is_branch0    : in  std_logic;
        alloc_ckpt_id0      : in  std_logic_vector(CKPT_ID_BITS-1 downto 0);

        alloc_val1          : in  std_logic;
        alloc_pc1           : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        alloc_rd_arch1      : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        alloc_rd_phys1      : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_old_phys1     : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        alloc_has_dest1     : in  std_logic;
        alloc_is_store1     : in  std_logic;
        alloc_is_branch1    : in  std_logic;
        alloc_ckpt_id1      : in  std_logic_vector(CKPT_ID_BITS-1 downto 0);

        rob_has_space1      : out std_logic;
        rob_has_space2      : out std_logic;
        alloc_idx0_out      : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        alloc_idx1_out      : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        -- CDB Completion Snooping
        cdb_bus             : in  cdb_bus_t;

        -- Branch Unit Resolution
        branch_resolved     : in  std_logic;
        branch_rob_idx      : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        branch_mispred      : in  std_logic;
        branch_target_pc    : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- In-Order Retirement Interface to Free List & cRAT
        commit_val0         : out std_logic;
        commit_rd_arch0     : out std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys0     : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_old_phys0    : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_is_store0    : out std_logic;
        commit_is_branch0   : out std_logic;
        commit_ckpt_id0     : out std_logic_vector(CKPT_ID_BITS-1 downto 0);

        commit_val1         : out std_logic;
        commit_rd_arch1     : out std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys1     : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_old_phys1    : out std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_is_store1    : out std_logic;
        commit_is_branch1   : out std_logic;
        commit_ckpt_id1     : out std_logic_vector(CKPT_ID_BITS-1 downto 0);

        -- CSR Instruction Port
        csr_en              : in  std_logic;
        csr_addr            : in  std_logic_vector(11 downto 0);
        csr_wdata           : in  std_logic_vector(XLEN-1 downto 0);
        csr_op              : in  std_logic_vector(1 downto 0);
        csr_rdata           : out std_logic_vector(XLEN-1 downto 0);
        mret_val            : in  std_logic;

        -- Interrupt Lines
        ext_int             : in  std_logic;
        timer_int           : in  std_logic;
        sw_int              : in  std_logic;

        -- Front-End Pipeline Redirects
        trap_redirect_valid : out std_logic;
        trap_redirect_pc    : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        branch_mispred_valid: out std_logic;
        branch_mispred_pc   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        branch_mispred_ckpt : out std_logic_vector(CKPT_ID_BITS-1 downto 0)
    );
end entity talos_commit_top;

architecture rtl of talos_commit_top is

    signal rob_trap_val   : std_logic;
    signal rob_trap_pc    : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal rob_trap_cause : std_logic_vector(4 downto 0);
    signal rob_trap_epc   : std_logic_vector(ADDR_WIDTH-1 downto 0);

    signal csr_int_pend   : std_logic;
    signal trap_vector    : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal mret_pc        : std_logic_vector(ADDR_WIDTH-1 downto 0);

    signal trap_fire_val  : std_logic;
    signal trap_fire_pc   : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal trap_fire_cau  : std_logic_vector(4 downto 0);
    signal trap_fire_tval : std_logic_vector(XLEN-1 downto 0);

begin

    -- 1. Reorder Buffer
    u_rob : entity work.talos_rob
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            flush               => flush or trap_fire_val,
            alloc_val0          => alloc_val0,
            alloc_pc0           => alloc_pc0,
            alloc_rd_arch0      => alloc_rd_arch0,
            alloc_rd_phys0      => alloc_rd_phys0,
            alloc_old_phys0     => alloc_old_phys0,
            alloc_has_dest0     => alloc_has_dest0,
            alloc_is_store0     => alloc_is_store0,
            alloc_is_branch0    => alloc_is_branch0,
            alloc_ckpt_id0      => alloc_ckpt_id0,
            alloc_val1          => alloc_val1,
            alloc_pc1           => alloc_pc1,
            alloc_rd_arch1      => alloc_rd_arch1,
            alloc_rd_phys1      => alloc_rd_phys1,
            alloc_old_phys1     => alloc_old_phys1,
            alloc_has_dest1     => alloc_has_dest1,
            alloc_is_store1     => alloc_is_store1,
            alloc_is_branch1    => alloc_is_branch1,
            alloc_ckpt_id1      => alloc_ckpt_id1,
            rob_has_space1      => rob_has_space1,
            rob_has_space2      => rob_has_space2,
            alloc_idx0_out      => alloc_idx0_out,
            alloc_idx1_out      => alloc_idx1_out,
            cdb_bus             => cdb_bus,
            branch_resolved     => branch_resolved,
            branch_rob_idx      => branch_rob_idx,
            branch_mispred      => branch_mispred,
            branch_target_pc    => branch_target_pc,
            commit_val0         => commit_val0,
            commit_rd_arch0     => commit_rd_arch0,
            commit_rd_phys0     => commit_rd_phys0,
            commit_old_phys0    => commit_old_phys0,
            commit_is_store0    => commit_is_store0,
            commit_is_branch0   => commit_is_branch0,
            commit_ckpt_id0     => commit_ckpt_id0,
            commit_val1         => commit_val1,
            commit_rd_arch1     => commit_rd_arch1,
            commit_rd_phys1     => commit_rd_phys1,
            commit_old_phys1    => commit_old_phys1,
            commit_is_store1    => commit_is_store1,
            commit_is_branch1   => commit_is_branch1,
            commit_ckpt_id1     => commit_ckpt_id1,
            trap_val            => rob_trap_val,
            trap_pc             => rob_trap_pc,
            trap_cause          => rob_trap_cause,
            trap_epc            => rob_trap_epc,
            mispred_val         => branch_mispred_valid,
            mispred_pc          => branch_mispred_pc,
            mispred_ckpt_id     => branch_mispred_ckpt
        );

    -- 2. Trap Controller
    u_trap_ctrl : entity work.talos_trap_ctrl
        port map (
            rob_trap_val    => rob_trap_val,
            rob_trap_cause  => rob_trap_cause,
            rob_trap_pc     => rob_trap_epc,
            csr_int_pending => csr_int_pend,
            ext_int         => ext_int,
            timer_int       => timer_int,
            sw_int          => sw_int,
            trap_fire_val   => trap_fire_val,
            trap_fire_pc    => trap_fire_pc,
            trap_fire_cause => trap_fire_cau,
            trap_fire_tval  => trap_fire_tval,
            is_interrupt    => open
        );

    -- 3. CSR Bank
    u_csr : entity work.talos_csr
        port map (
            clk          => clk,
            rst_n        => rst_n,
            csr_en       => csr_en,
            csr_addr     => csr_addr,
            csr_wdata    => csr_wdata,
            csr_op       => csr_op,
            csr_rdata    => csr_rdata,
            trap_in_val  => trap_fire_val,
            trap_in_pc   => trap_fire_pc,
            trap_in_cau  => trap_fire_cau,
            trap_in_tval => trap_fire_tval,
            mret_val     => mret_val,
            mret_pc      => mret_pc,
            ext_int      => ext_int,
            timer_int    => timer_int,
            sw_int       => sw_int,
            trap_vector  => trap_vector,
            int_pending  => csr_int_pend
        );

    -- Redirect arbitration: MRET or Trap
    process(mret_val, mret_pc, trap_fire_val, trap_vector)
    begin
        if mret_val = '1' then
            trap_redirect_valid <= '1';
            trap_redirect_pc    <= mret_pc;
        elsif trap_fire_val = '1' then
            trap_redirect_valid <= '1';
            trap_redirect_pc    <= trap_vector;
        else
            trap_redirect_valid <= '0';
            trap_redirect_pc    <= (others => '0');
        end if;
    end process;

end architecture rtl;
