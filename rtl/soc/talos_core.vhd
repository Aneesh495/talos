-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Core: Top-Level Out-of-Order Execution CPU Core
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_rv32_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_core is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        -- Interrupt Lines
        ext_int     : in  std_logic;
        timer_int   : in  std_logic;
        sw_int      : in  std_logic;

        -- External System AXI4-Full Master Interface
        m_axi_m2s   : out axi4_m2s_t;
        m_axi_s2m   : in  axi4_s2m_t
    );
end entity talos_core;

architecture rtl of talos_core is

    -- Front-End / Fetch Signals
    signal fetch_bundle       : fetch_bundle_t;
    signal fetch_empty        : std_logic;
    signal decode_pop_cnt     : integer range 0 to FETCH_WIDTH;

    signal trap_redir_val     : std_logic;
    signal trap_redir_pc      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal br_mispred_val     : std_logic;
    signal br_mispred_pc      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal br_mispred_ckpt    : std_logic_vector(CKPT_ID_BITS-1 downto 0);

    signal br_resolved        : std_logic;
    signal br_rob_idx         : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal br_mispred_strobe  : std_logic;
    signal br_target_pc       : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- I-Cache AXI4 Refill Ports
    signal icache_araddr      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal icache_arlen       : std_logic_vector(7 downto 0);
    signal icache_arsize      : std_logic_vector(2 downto 0);
    signal icache_arburst     : std_logic_vector(1 downto 0);
    signal icache_arvalid     : std_logic;
    signal icache_arready     : std_logic;
    signal icache_rdata       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal icache_rresp       : std_logic_vector(1 downto 0);
    signal icache_rlast       : std_logic;
    signal icache_rvalid      : std_logic;
    signal icache_rready      : std_logic;

    -- Decode Stage Signals
    signal decode_bundle      : decode_bundle_t;

    -- Rename Subsystem Signals
    signal stall_rename       : std_logic;
    signal rename_ready       : std_logic;
    signal rename_bundle      : rename_bundle_t;

    -- Dispatch Unit Signals
    signal rob_has_space1     : std_logic;
    signal rob_has_space2     : std_logic;
    signal rob_alloc_idx0     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal rob_alloc_idx1     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);

    signal rs_alu_ready       : std_logic;
    signal rs_muldiv_ready    : std_logic;
    signal rs_mem_ready       : std_logic;
    signal rs_fpu_ready       : std_logic;
    signal lsq_ready          : std_logic;
    signal lsq_alloc_idx      : std_logic_vector(SQ_INDEX_BITS-1 downto 0);

    signal rob_alloc_val0     : std_logic;
    signal rob_alloc_val1     : std_logic;
    signal lsq_alloc_val0     : std_logic;
    signal lsq_alloc_val1     : std_logic;

    signal rs_alu_push_val0   : std_logic;
    signal rs_alu_push_pkt0   : rename_pkt_t;
    signal rs_alu_push_val1   : std_logic;
    signal rs_alu_push_pkt1   : rename_pkt_t;
    signal rs_md_push_val     : std_logic;
    signal rs_md_push_pkt     : rename_pkt_t;
    signal rs_mem_push_val    : std_logic;
    signal rs_mem_push_pkt    : rename_pkt_t;
    signal rs_fpu_push_val    : std_logic;
    signal rs_fpu_push_pkt    : rename_pkt_t;

    -- Reservation Station Issues
    signal rs_alu_iss_val0    : std_logic;
    signal rs_alu_iss_pkt0    : rename_pkt_t;
    signal rs_alu_iss_val1    : std_logic;
    signal rs_alu_iss_pkt1    : rename_pkt_t;

    signal rs_md_iss_val      : std_logic;
    signal rs_md_iss_pkt      : rename_pkt_t;

    signal rs_mem_iss_val     : std_logic;
    signal rs_mem_iss_pkt     : rename_pkt_t;

    signal rs_fpu_iss_val     : std_logic;
    signal rs_fpu_iss_pkt     : rename_pkt_t;

    -- PRF Read Data
    signal prf_rdata0         : std_logic_vector(XLEN-1 downto 0);
    signal prf_rdata1         : std_logic_vector(XLEN-1 downto 0);
    signal prf_rdata2         : std_logic_vector(XLEN-1 downto 0);
    signal prf_rdata3         : std_logic_vector(XLEN-1 downto 0);
    signal prf_rdata4         : std_logic_vector(XLEN-1 downto 0);
    signal prf_rdata5         : std_logic_vector(XLEN-1 downto 0);

    -- Functional Unit Outputs
    signal alu0_res           : std_logic_vector(XLEN-1 downto 0);
    signal alu1_res           : std_logic_vector(XLEN-1 downto 0);
    signal br_act_taken       : std_logic;
    signal br_act_target      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal br_link_val        : std_logic_vector(XLEN-1 downto 0);
    signal br_mispred_det     : std_logic;
    signal br_recov_pc        : std_logic_vector(ADDR_WIDTH-1 downto 0);

    signal mul_resp_val       : std_logic;
    signal mul_resp_res       : std_logic_vector(XLEN-1 downto 0);
    signal mul_rob_idx_out    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal mul_rd_phys_out    : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    signal div_resp_val       : std_logic;
    signal div_resp_res       : std_logic_vector(XLEN-1 downto 0);
    signal div_rob_idx_out    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal div_rd_phys_out    : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    signal fpu_resp_val       : std_logic;
    signal fpu_resp_data      : std_logic_vector(XLEN-1 downto 0);
    signal fpu_rob_idx_out    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal fpu_rd_phys_out    : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    -- Common Data Bus (CDB)
    signal cdb_bus            : cdb_bus_t;

    -- Memory Subsystem Outputs
    signal mem_cdb_val        : std_logic;
    signal mem_cdb_tag        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal mem_cdb_rob_idx    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal mem_cdb_data       : std_logic_vector(XLEN-1 downto 0);
    signal mem_cdb_exc        : std_logic;
    signal mem_cdb_exc_cause  : std_logic_vector(4 downto 0);
    signal mem_order_viol     : std_logic;
    signal viol_rob_idx       : std_logic_vector(ROB_INDEX_BITS-1 downto 0);

    -- D-Cache AXI4 Refill Ports
    signal dcache_araddr      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal dcache_arlen       : std_logic_vector(7 downto 0);
    signal dcache_arsize      : std_logic_vector(2 downto 0);
    signal dcache_arburst     : std_logic_vector(1 downto 0);
    signal dcache_arvalid     : std_logic;
    signal dcache_arready     : std_logic;
    signal dcache_rdata       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal dcache_rresp       : std_logic_vector(1 downto 0);
    signal dcache_rlast       : std_logic;
    signal dcache_rvalid      : std_logic;
    signal dcache_rready      : std_logic;

    -- D-Cache AXI4 Write-Back Ports
    signal dcache_awaddr      : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal dcache_awlen       : std_logic_vector(7 downto 0);
    signal dcache_awsize      : std_logic_vector(2 downto 0);
    signal dcache_awburst     : std_logic_vector(1 downto 0);
    signal dcache_awvalid     : std_logic;
    signal dcache_awready     : std_logic;
    signal dcache_wdata       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal dcache_wstrb       : std_logic_vector(3 downto 0);
    signal dcache_wlast       : std_logic;
    signal dcache_wvalid      : std_logic;
    signal dcache_wready      : std_logic;
    signal dcache_bvalid      : std_logic;
    signal dcache_bready      : std_logic;

    -- Commit Retirement Signals
    signal commit_val0        : std_logic;
    signal commit_rd_arch0    : std_logic_vector(ARCH_REG_BITS-1 downto 0);
    signal commit_rd_phys0    : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal commit_old_phys0   : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal commit_is_store0   : std_logic;
    signal commit_is_branch0  : std_logic;
    signal commit_ckpt_id0    : std_logic_vector(CKPT_ID_BITS-1 downto 0);

    signal commit_val1        : std_logic;
    signal commit_rd_arch1    : std_logic_vector(ARCH_REG_BITS-1 downto 0);
    signal commit_rd_phys1    : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal commit_old_phys1   : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal commit_is_store1   : std_logic;
    signal commit_is_branch1  : std_logic;
    signal commit_ckpt_id1    : std_logic_vector(CKPT_ID_BITS-1 downto 0);

    signal csr_rdata          : std_logic_vector(XLEN-1 downto 0);

    -- Branch Resolution Multiplexing
    signal alu0_final_res     : std_logic_vector(XLEN-1 downto 0);
    signal alu0_src2          : std_logic_vector(XLEN-1 downto 0);
    signal alu1_src2          : std_logic_vector(XLEN-1 downto 0);

begin

    -- Select link register value for jumps, or ALU result for standard instructions
    alu0_final_res <= br_link_val when rs_alu_iss_pkt0.is_jump = '1' else alu0_res;
    alu0_src2      <= rs_alu_iss_pkt0.imm when rs_alu_iss_pkt0.use_imm = '1' else prf_rdata1;
    alu1_src2      <= rs_alu_iss_pkt1.imm when rs_alu_iss_pkt1.use_imm = '1' else prf_rdata3;

    br_resolved       <= rs_alu_iss_val0 and (rs_alu_iss_pkt0.is_branch or rs_alu_iss_pkt0.is_jump);
    br_rob_idx        <= rs_alu_iss_pkt0.rob_idx;
    br_mispred_strobe <= br_mispred_det;
    br_target_pc      <= br_recov_pc;

    -- 1. Front-End Subsystem
    u_front : entity work.talos_front_top
        port map (
            clk                  => clk,
            rst_n                => rst_n,
            stall                => stall_rename,
            flush                => br_mispred_val or trap_redir_val or mem_order_viol,
            trap_redirect_valid  => trap_redir_val,
            trap_redirect_pc     => trap_redir_pc,
            branch_mispred_valid => br_mispred_val,
            branch_mispred_pc    => br_mispred_pc,
            restore_tos          => (others => '0'),
            resolve_valid        => br_resolved,
            resolve_pc           => rs_alu_iss_pkt0.pc,
            resolve_target       => br_act_target,
            resolve_ghr          => (others => '0'),
            resolve_taken        => br_act_taken,
            resolve_mispred      => br_mispred_det,
            resolve_is_call      => '0',
            resolve_is_return    => '0',
            decode_pop_count     => decode_pop_cnt,
            fetch_bundle_out     => fetch_bundle,
            fetch_empty          => fetch_empty,
            m_axi_araddr         => icache_araddr,
            m_axi_arlen          => icache_arlen,
            m_axi_arsize         => icache_arsize,
            m_axi_arburst        => icache_arburst,
            m_axi_arvalid        => icache_arvalid,
            m_axi_arready        => icache_arready,
            m_axi_rdata          => icache_rdata,
            m_axi_rresp          => icache_rresp,
            m_axi_rlast          => icache_rlast,
            m_axi_rvalid         => icache_rvalid,
            m_axi_rready         => icache_rready
        );

    -- 2. Dual-Issue Decode Stage
    u_decode : entity work.talos_decode_stage
        port map (
            clk              => clk,
            rst_n            => rst_n,
            flush            => br_mispred_val or trap_redir_val or mem_order_viol,
            stall            => stall_rename,
            fetch_bundle     => fetch_bundle,
            fetch_empty      => fetch_empty,
            decode_pop_count => decode_pop_cnt,
            decode_bundle    => decode_bundle
        );

    -- 3. Speculative Register Renaming
    u_rename : entity work.talos_rename_top
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            flush               => trap_redir_val or mem_order_viol,
            stall               => stall_rename,
            decode_bundle       => decode_bundle,
            rename_ready        => rename_ready,
            current_ghr         => (others => '0'),
            current_tos         => (others => '0'),
            cdb_bus             => cdb_bus,
            rollback_valid      => br_mispred_val,
            rollback_id         => br_mispred_ckpt,
            commit_val0         => commit_val0,
            commit_rd_arch0     => commit_rd_arch0,
            commit_rd_phys0     => commit_rd_phys0,
            commit_old_phys0    => commit_old_phys0,
            commit_val1         => commit_val1,
            commit_rd_arch1     => commit_rd_arch1,
            commit_rd_phys1     => commit_rd_phys1,
            commit_old_phys1    => commit_old_phys1,
            commit_is_branch0   => commit_is_branch0,
            commit_ckpt_id0     => commit_ckpt_id0,
            commit_is_branch1   => commit_is_branch1,
            commit_ckpt_id1     => commit_ckpt_id1,
            rename_bundle       => rename_bundle
        );

    -- 4. Dual-Issue Dispatch Unit
    u_dispatch : entity work.talos_dispatch
        port map (
            clk              => clk,
            rst_n            => rst_n,
            flush            => br_mispred_val or trap_redir_val or mem_order_viol,
            rename_bundle    => rename_bundle,
            stall_rename     => stall_rename,
            rob_has_space2   => rob_has_space2,
            rob_has_space1   => rob_has_space1,
            rob_alloc_idx0   => rob_alloc_idx0,
            rob_alloc_idx1   => rob_alloc_idx1,
            rs_alu_ready     => rs_alu_ready,
            rs_muldiv_ready  => rs_muldiv_ready,
            rs_mem_ready     => rs_mem_ready,
            rs_fpu_ready     => rs_fpu_ready,
            lsq_ready        => lsq_ready,
            lsq_alloc_idx0   => lsq_alloc_idx,
            lsq_alloc_idx1   => (others => '0'),
            rob_alloc_val0   => rob_alloc_val0,
            rob_alloc_val1   => rob_alloc_val1,
            lsq_alloc_val0   => lsq_alloc_val0,
            lsq_alloc_val1   => lsq_alloc_val1,
            rs_alu_push_val0 => rs_alu_push_val0,
            rs_alu_push_pkt0 => rs_alu_push_pkt0,
            rs_alu_push_val1 => rs_alu_push_val1,
            rs_alu_push_pkt1 => rs_alu_push_pkt1,
            rs_md_push_val   => rs_md_push_val,
            rs_md_push_pkt   => rs_md_push_pkt,
            rs_mem_push_val  => rs_mem_push_val,
            rs_mem_push_pkt  => rs_mem_push_pkt,
            rs_fpu_push_val  => rs_fpu_push_val,
            rs_fpu_push_pkt  => rs_fpu_push_pkt
        );

    -- 5. Unified ALU Reservation Station
    u_rs_alu : entity work.talos_rs_alu
        port map (
            clk        => clk,
            rst_n      => rst_n,
            flush      => br_mispred_val or trap_redir_val or mem_order_viol,
            push_val0  => rs_alu_push_val0,
            push_pkt0  => rs_alu_push_pkt0,
            push_val1  => rs_alu_push_val1,
            push_pkt1  => rs_alu_push_pkt1,
            rs_ready   => rs_alu_ready,
            cdb_bus    => cdb_bus,
            issue_val0 => rs_alu_iss_val0,
            issue_pkt0 => rs_alu_iss_pkt0,
            issue_val1 => rs_alu_iss_val1,
            issue_pkt1 => rs_alu_iss_pkt1
        );

    -- 6. Multiplier / Divider Reservation Station
    u_rs_md : entity work.talos_rs_muldiv
        port map (
            clk       => clk,
            rst_n     => rst_n,
            flush     => br_mispred_val or trap_redir_val or mem_order_viol,
            push_val  => rs_md_push_val,
            push_pkt  => rs_md_push_pkt,
            rs_ready  => rs_muldiv_ready,
            cdb_bus   => cdb_bus,
            issue_val => rs_md_iss_val,
            issue_pkt => rs_md_iss_pkt
        );

    -- 7. Memory Reservation Station
    u_rs_mem : entity work.talos_rs_mem
        port map (
            clk       => clk,
            rst_n     => rst_n,
            flush     => br_mispred_val or trap_redir_val or mem_order_viol,
            push_val  => rs_mem_push_val,
            push_pkt  => rs_mem_push_pkt,
            rs_ready  => rs_mem_ready,
            cdb_bus   => cdb_bus,
            issue_val => rs_mem_iss_val,
            issue_pkt => rs_mem_iss_pkt
        );

    -- 8. FPU Reservation Station
    u_rs_fpu : entity work.talos_rs_fpu
        port map (
            clk       => clk,
            rst_n     => rst_n,
            flush     => br_mispred_val or trap_redir_val or mem_order_viol,
            push_val  => rs_fpu_push_val,
            push_pkt  => rs_fpu_push_pkt,
            rs_ready  => rs_fpu_ready,
            cdb_bus   => cdb_bus,
            issue_val => rs_fpu_iss_val,
            issue_pkt => rs_fpu_iss_pkt
        );

    -- 9. Physical Register File
    u_prf : entity work.talos_prf
        port map (
            clk     => clk,
            rst_n   => rst_n,
            raddr0  => rs_alu_iss_pkt0.rs1_phys,
            rdata0  => prf_rdata0,
            raddr1  => rs_alu_iss_pkt0.rs2_phys,
            rdata1  => prf_rdata1,
            raddr2  => rs_alu_iss_pkt1.rs1_phys,
            rdata2  => prf_rdata2,
            raddr3  => rs_alu_iss_pkt1.rs2_phys,
            rdata3  => prf_rdata3,
            raddr4  => rs_mem_iss_pkt.rs1_phys,
            rdata4  => prf_rdata4,
            raddr5  => rs_mem_iss_pkt.rs2_phys,
            rdata5  => prf_rdata5,
            cdb_bus => cdb_bus
        );

    -- 10. ALU 0
    u_alu0 : entity work.talos_alu
        port map (
            alu_op => rs_alu_iss_pkt0.alu_op,
            src1   => prf_rdata0,
            src2   => alu0_src2,
            pc     => rs_alu_iss_pkt0.pc,
            imm    => rs_alu_iss_pkt0.imm,
            res    => alu0_res,
            zero   => open
        );

    -- 11. Branch Resolution Unit
    u_branch : entity work.talos_branch_unit
        port map (
            br_op         => rs_alu_iss_pkt0.br_op,
            src1          => prf_rdata0,
            src2          => prf_rdata1,
            pc            => rs_alu_iss_pkt0.pc,
            imm           => rs_alu_iss_pkt0.imm,
            pred_taken    => rs_alu_iss_pkt0.pred_taken,
            pred_target   => rs_alu_iss_pkt0.pred_target,
            actual_taken  => br_act_taken,
            actual_target => br_act_target,
            link_val      => br_link_val,
            mispredicted  => br_mispred_det,
            recovery_pc   => br_recov_pc
        );

    -- 12. ALU 1
    u_alu1 : entity work.talos_alu
        port map (
            alu_op => rs_alu_iss_pkt1.alu_op,
            src1   => prf_rdata2,
            src2   => alu1_src2,
            pc     => rs_alu_iss_pkt1.pc,
            imm    => rs_alu_iss_pkt1.imm,
            res    => alu1_res,
            zero   => open
        );

    -- 13. Pipelined Multiplier
    u_mult : entity work.talos_multiplier
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => br_mispred_val or trap_redir_val or mem_order_viol,
            req_val     => rs_md_iss_val,
            md_op       => rs_md_iss_pkt.md_op,
            src1        => prf_rdata0,
            src2        => prf_rdata1,
            rob_idx_in  => rs_md_iss_pkt.rob_idx,
            rd_phys_in  => rs_md_iss_pkt.rd_phys,
            resp_val    => mul_resp_val,
            resp_res    => mul_resp_res,
            rob_idx_out => mul_rob_idx_out,
            rd_phys_out => mul_rd_phys_out
        );

    -- 14. Hardware Integer Divider
    u_div : entity work.talos_divider
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => br_mispred_val or trap_redir_val or mem_order_viol,
            req_val     => rs_md_iss_val,
            md_op       => rs_md_iss_pkt.md_op,
            src1        => prf_rdata0,
            src2        => prf_rdata1,
            rob_idx_in  => rs_md_iss_pkt.rob_idx,
            rd_phys_in  => rs_md_iss_pkt.rd_phys,
            busy        => open,
            resp_val    => div_resp_val,
            resp_res    => div_resp_res,
            rob_idx_out => div_rob_idx_out,
            rd_phys_out => div_rd_phys_out
        );

    -- 15. FPU Pipeline
    u_fpu : entity work.talos_fpu_top
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => br_mispred_val or trap_redir_val or mem_order_viol,
            req_val     => rs_fpu_iss_val,
            fpu_op      => rs_fpu_iss_pkt.fpu_op,
            src1        => prf_rdata0,
            src2        => prf_rdata1,
            src3        => (others => '0'),
            rm          => "000",
            rob_idx_in  => rs_fpu_iss_pkt.rob_idx,
            rd_phys_in  => rs_fpu_iss_pkt.rd_phys,
            resp_val    => fpu_resp_val,
            resp_data   => fpu_resp_data,
            resp_flags  => open,
            rob_idx_out => fpu_rob_idx_out,
            rd_phys_out => fpu_rd_phys_out
        );

    -- 16. Common Data Bus Arbiter
    u_cdb : entity work.talos_cdb_arbiter
        port map (
            alu0_val       => rs_alu_iss_val0 and rs_alu_iss_pkt0.has_dest,
            alu0_tag       => rs_alu_iss_pkt0.rd_phys,
            alu0_rob_idx   => rs_alu_iss_pkt0.rob_idx,
            alu0_res       => alu0_final_res,
            alu0_exc       => rs_alu_iss_pkt0.illegal_op,
            alu0_exc_cause => CAUSE_ILLEGAL_INSTR,
            alu1_val       => rs_alu_iss_val1 and rs_alu_iss_pkt1.has_dest,
            alu1_tag       => rs_alu_iss_pkt1.rd_phys,
            alu1_rob_idx   => rs_alu_iss_pkt1.rob_idx,
            alu1_res       => alu1_res,
            mul_val        => mul_resp_val,
            mul_tag        => mul_rd_phys_out,
            mul_rob_idx    => mul_rob_idx_out,
            mul_res        => mul_resp_res,
            div_val        => div_resp_val,
            div_tag        => div_rd_phys_out,
            div_rob_idx    => div_rob_idx_out,
            div_res        => div_resp_res,
            mem_val        => mem_cdb_val,
            mem_tag        => mem_cdb_tag,
            mem_rob_idx    => mem_cdb_rob_idx,
            mem_res        => mem_cdb_data,
            mem_exc        => mem_cdb_exc,
            mem_exc_cause  => mem_cdb_exc_cause,
            fpu_val        => fpu_resp_val,
            fpu_tag        => fpu_rd_phys_out,
            fpu_rob_idx    => fpu_rob_idx_out,
            fpu_res        => fpu_resp_data,
            cdb_out        => cdb_bus
        );

    -- 17. Memory Subsystem
    u_mem : entity work.talos_mem_top
        port map (
            clk                 => clk,
            rst_n               => rst_n,
            flush               => br_mispred_val or trap_redir_val,
            alloc_load          => lsq_alloc_val0 or lsq_alloc_val1,
            alloc_store         => lsq_alloc_val0 or lsq_alloc_val1,
            alloc_rob_idx       => rs_mem_iss_pkt.rob_idx,
            alloc_rd_phys       => rs_mem_iss_pkt.rd_phys,
            alloc_mem_op        => rs_mem_iss_pkt.mem_op,
            lsq_ready           => lsq_ready,
            alloc_sq_idx        => lsq_alloc_idx,
            agu_val             => rs_mem_iss_val,
            agu_is_store        => rs_mem_iss_pkt.is_store,
            agu_addr            => std_logic_vector(unsigned(prf_rdata4) + unsigned(rs_mem_iss_pkt.imm)),
            agu_data            => prf_rdata5,
            agu_rob_idx         => rs_mem_iss_pkt.rob_idx,
            agu_rd_phys         => rs_mem_iss_pkt.rd_phys,
            agu_mem_op          => rs_mem_iss_pkt.mem_op,
            commit_store        => commit_is_store0 or commit_is_store1,
            commit_rob_idx      => rob_alloc_idx0,
            mem_cdb_val         => mem_cdb_val,
            mem_cdb_tag         => mem_cdb_tag,
            mem_cdb_rob_idx     => mem_cdb_rob_idx,
            mem_cdb_data        => mem_cdb_data,
            mem_cdb_exc         => mem_cdb_exc,
            mem_cdb_exc_cause   => mem_cdb_exc_cause,
            mem_order_violation => mem_order_viol,
            violation_rob_idx   => viol_rob_idx,
            m_axi_araddr        => dcache_araddr,
            m_axi_arlen         => dcache_arlen,
            m_axi_arsize        => dcache_arsize,
            m_axi_arburst       => dcache_arburst,
            m_axi_arvalid       => dcache_arvalid,
            m_axi_arready       => dcache_arready,
            m_axi_rdata         => dcache_rdata,
            m_axi_rresp         => dcache_rresp,
            m_axi_rlast         => dcache_rlast,
            m_axi_rvalid        => dcache_rvalid,
            m_axi_rready        => dcache_rready,
            m_axi_awaddr        => dcache_awaddr,
            m_axi_awlen         => dcache_awlen,
            m_axi_awsize        => dcache_awsize,
            m_axi_awburst       => dcache_awburst,
            m_axi_awvalid       => dcache_awvalid,
            m_axi_awready       => dcache_awready,
            m_axi_wdata         => dcache_wdata,
            m_axi_wstrb         => dcache_wstrb,
            m_axi_wlast         => dcache_wlast,
            m_axi_wvalid        => dcache_wvalid,
            m_axi_wready        => dcache_wready,
            m_axi_bvalid        => dcache_bvalid,
            m_axi_bready        => dcache_bready
        );

    -- 18. Commit Subsystem (ROB + CSR Bank + Trap Arbiter)
    u_commit : entity work.talos_commit_top
        port map (
            clk                  => clk,
            rst_n                => rst_n,
            flush                => br_mispred_val or mem_order_viol,
            alloc_val0           => rob_alloc_val0,
            alloc_pc0            => rename_bundle(0).pc,
            alloc_rd_arch0       => rename_bundle(0).rd_arch,
            alloc_rd_phys0       => rename_bundle(0).rd_phys,
            alloc_old_phys0      => rename_bundle(0).old_rd_phys,
            alloc_has_dest0      => rename_bundle(0).has_dest,
            alloc_is_store0      => rename_bundle(0).is_store,
            alloc_is_branch0     => rename_bundle(0).is_branch,
            alloc_ckpt_id0       => rename_bundle(0).ckpt_id,
            alloc_val1           => rob_alloc_val1,
            alloc_pc1            => rename_bundle(1).pc,
            alloc_rd_arch1       => rename_bundle(1).rd_arch,
            alloc_rd_phys1       => rename_bundle(1).rd_phys,
            alloc_old_phys1      => rename_bundle(1).old_rd_phys,
            alloc_has_dest1      => rename_bundle(1).has_dest,
            alloc_is_store1      => rename_bundle(1).is_store,
            alloc_is_branch1     => rename_bundle(1).is_branch,
            alloc_ckpt_id1       => rename_bundle(1).ckpt_id,
            rob_has_space1       => rob_has_space1,
            rob_has_space2       => rob_has_space2,
            alloc_idx0_out       => rob_alloc_idx0,
            alloc_idx1_out       => rob_alloc_idx1,
            cdb_bus              => cdb_bus,
            branch_resolved      => br_resolved,
            branch_rob_idx       => br_rob_idx,
            branch_mispred       => br_mispred_strobe,
            branch_target_pc     => br_target_pc,
            commit_val0          => commit_val0,
            commit_rd_arch0      => commit_rd_arch0,
            commit_rd_phys0      => commit_rd_phys0,
            commit_old_phys0     => commit_old_phys0,
            commit_is_store0     => commit_is_store0,
            commit_is_branch0    => commit_is_branch0,
            commit_ckpt_id0      => commit_ckpt_id0,
            commit_val1          => commit_val1,
            commit_rd_arch1      => commit_rd_arch1,
            commit_rd_phys1      => commit_rd_phys1,
            commit_old_phys1     => commit_old_phys1,
            commit_is_store1     => commit_is_store1,
            commit_is_branch1    => commit_is_branch1,
            commit_ckpt_id1      => commit_ckpt_id1,
            csr_en               => rs_alu_iss_val0 and rs_alu_iss_pkt0.is_csr,
            csr_addr             => rs_alu_iss_pkt0.imm(11 downto 0),
            csr_wdata            => prf_rdata0,
            csr_op               => rs_alu_iss_pkt0.imm(13 downto 12),
            csr_rdata            => csr_rdata,
            mret_val             => '0',
            ext_int              => ext_int,
            timer_int            => timer_int,
            sw_int               => sw_int,
            trap_redirect_valid  => trap_redir_val,
            trap_redirect_pc     => trap_redir_pc,
            branch_mispred_valid => br_mispred_val,
            branch_mispred_pc    => br_mispred_pc,
            branch_mispred_ckpt  => br_mispred_ckpt
        );

    -- 19. AXI4 Master Arbiter
    u_axi_master : entity work.talos_axi4_master
        port map (
            clk            => clk,
            rst_n          => rst_n,
            icache_araddr  => icache_araddr,
            icache_arlen   => icache_arlen,
            icache_arsize  => icache_arsize,
            icache_arburst => icache_arburst,
            icache_arvalid => icache_arvalid,
            icache_arready => icache_arready,
            icache_rdata   => icache_rdata,
            icache_rresp   => icache_rresp,
            icache_rlast   => icache_rlast,
            icache_rvalid  => icache_rvalid,
            icache_rready  => icache_rready,
            dcache_araddr  => dcache_araddr,
            dcache_arlen   => dcache_arlen,
            dcache_arsize  => dcache_arsize,
            dcache_arburst => dcache_arburst,
            dcache_arvalid => dcache_arvalid,
            dcache_arready => dcache_arready,
            dcache_rdata   => dcache_rdata,
            dcache_rresp   => dcache_rresp,
            dcache_rlast   => dcache_rlast,
            dcache_rvalid  => dcache_rvalid,
            dcache_rready  => dcache_rready,
            dcache_awaddr  => dcache_awaddr,
            dcache_awlen   => dcache_awlen,
            dcache_awsize  => dcache_awsize,
            dcache_awburst => dcache_awburst,
            dcache_awvalid => dcache_awvalid,
            dcache_awready => dcache_awready,
            dcache_wdata   => dcache_wdata,
            dcache_wstrb   => dcache_wstrb,
            dcache_wlast   => dcache_wlast,
            dcache_wvalid  => dcache_wvalid,
            dcache_wready  => dcache_wready,
            dcache_bvalid  => dcache_bvalid,
            dcache_bready  => dcache_bready,
            m_axi_m2s      => m_axi_m2s,
            m_axi_s2m      => m_axi_s2m
        );

end architecture rtl;
