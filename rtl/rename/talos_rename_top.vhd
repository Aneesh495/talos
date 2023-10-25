-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Rename: Top-Level Integration (Free List, RAT, Checkpoint Store, cRAT)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_rename_top is
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        flush               : in  std_logic;
        stall               : in  std_logic;

        -- Ingress from Decode Stage
        decode_bundle       : in  decode_bundle_t;
        rename_ready        : out std_logic;

        -- Current Branch Predictor Context for Checkpointing
        current_ghr         : in  std_logic_vector(9 downto 0);
        current_tos         : in  std_logic_vector(3 downto 0);

        -- Common Data Bus Snooping (Ready Bit Updates)
        cdb_bus             : in  cdb_bus_t;

        -- Branch Misprediction Recovery (Rollback)
        rollback_valid      : in  std_logic;
        rollback_id         : in  std_logic_vector(CKPT_ID_BITS-1 downto 0);

        -- In-Order Retirement Free & cRAT Updates (from ROB)
        commit_val0         : in  std_logic;
        commit_rd_arch0     : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys0     : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_old_phys0    : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);

        commit_val1         : in  std_logic;
        commit_rd_arch1     : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        commit_rd_phys1     : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        commit_old_phys1    : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);

        commit_is_branch0   : in  std_logic;
        commit_ckpt_id0     : in  std_logic_vector(CKPT_ID_BITS-1 downto 0);
        commit_is_branch1   : in  std_logic;
        commit_ckpt_id1     : in  std_logic_vector(CKPT_ID_BITS-1 downto 0);

        -- Egress to Dispatch Stage
        rename_bundle       : out rename_bundle_t
    );
end entity talos_rename_top;

architecture rtl of talos_rename_top is

    -- Free List signals
    signal alloc_req0       : std_logic;
    signal alloc_req1       : std_logic;
    signal alloc_tag0       : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal alloc_tag1       : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal fl_alloc_ready   : std_logic;
    signal fl_current_mask  : std_logic_vector(PHYS_REG_COUNT-1 downto 0);

    -- RAT signals
    signal rs1_phys0        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal rs1_ready0       : std_logic;
    signal rs2_phys0        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal rs2_ready0       : std_logic;
    signal old_rd_phys0     : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    signal rs1_phys1        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal rs1_ready1       : std_logic;
    signal rs2_phys1        : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal rs2_ready1       : std_logic;
    signal old_rd_phys1     : std_logic_vector(PHYS_REG_BITS-1 downto 0);

    signal current_rat      : std_logic_vector(ARCH_REG_COUNT*PHYS_REG_BITS-1 downto 0);
    signal current_ready    : std_logic_vector(PHYS_REG_COUNT-1 downto 0);

    -- Checkpoint Store signals
    signal ckpt_alloc_req   : std_logic;
    signal ckpt_alloc_id    : std_logic_vector(CKPT_ID_BITS-1 downto 0);
    signal ckpt_ready       : std_logic;
    signal release_id_i     : std_logic_vector(CKPT_ID_BITS-1 downto 0);

    signal rb_rat_table     : std_logic_vector(ARCH_REG_COUNT*PHYS_REG_BITS-1 downto 0);
    signal rb_ready_mask    : std_logic_vector(PHYS_REG_COUNT-1 downto 0);
    signal rb_free_mask     : std_logic_vector(PHYS_REG_COUNT-1 downto 0);

    -- cRAT signals
    signal crat_table       : std_logic_vector(ARCH_REG_COUNT*PHYS_REG_BITS-1 downto 0);

    -- Internal bundle registers
    signal out_bundle_reg   : rename_bundle_t := (others => RENAME_PKT_ZERO);

begin

    -- Free list allocation requests
    alloc_req0 <= decode_bundle(0).valid and decode_bundle(0).has_dest and not stall;
    alloc_req1 <= decode_bundle(1).valid and decode_bundle(1).has_dest and not stall;

    -- Checkpoint allocation: either instruction in the bundle is a branch
    ckpt_alloc_req <= (decode_bundle(0).is_branch or decode_bundle(1).is_branch) and not stall;

    rename_ready <= fl_alloc_ready and (ckpt_ready or not ckpt_alloc_req);

    -- 1. Free List
    u_free_list : entity work.talos_free_list
        port map (
            clk              => clk,
            rst_n            => rst_n,
            alloc_req0       => alloc_req0,
            alloc_req1       => alloc_req1,
            alloc_tag0       => alloc_tag0,
            alloc_tag1       => alloc_tag1,
            alloc_ready      => fl_alloc_ready,
            commit_free_val0 => commit_val0,
            commit_free_tag0 => commit_old_phys0,
            commit_free_val1 => commit_val1,
            commit_free_tag1 => commit_old_phys1,
            restore_valid    => rollback_valid,
            restore_mask     => rb_free_mask,
            current_mask     => fl_current_mask
        );

    -- 2. Speculative RAT
    u_rat : entity work.talos_rat
        port map (
            clk                => clk,
            rst_n              => rst_n,
            ren_req0           => decode_bundle(0).valid and not stall,
            rs1_arch0          => decode_bundle(0).rs1_arch,
            rs2_arch0          => decode_bundle(0).rs2_arch,
            rd_arch0           => decode_bundle(0).rd_arch,
            alloc_tag0         => alloc_tag0,
            has_dest0          => decode_bundle(0).has_dest,
            rs1_phys0          => rs1_phys0,
            rs1_ready0         => rs1_ready0,
            rs2_phys0          => rs2_phys0,
            rs2_ready0         => rs2_ready0,
            old_rd_phys0       => old_rd_phys0,
            ren_req1           => decode_bundle(1).valid and not stall,
            rs1_arch1          => decode_bundle(1).rs1_arch,
            rs2_arch1          => decode_bundle(1).rs2_arch,
            rd_arch1           => decode_bundle(1).rd_arch,
            alloc_tag1         => alloc_tag1,
            has_dest1          => decode_bundle(1).has_dest,
            rs1_phys1          => rs1_phys1,
            rs1_ready1         => rs1_ready1,
            rs2_phys1          => rs2_phys1,
            rs2_ready1         => rs2_ready1,
            old_rd_phys1       => old_rd_phys1,
            cdb_bus            => cdb_bus,
            restore_valid      => rollback_valid,
            restore_rat_table  => rb_rat_table,
            restore_ready_mask => rb_ready_mask,
            current_rat_table  => current_rat,
            current_ready_mask => current_ready
        );

    release_id_i <= commit_ckpt_id0 when commit_is_branch0 = '1' else commit_ckpt_id1;

    -- 3. Checkpoint Store
    u_checkpoint : entity work.talos_checkpoint
        port map (
            clk                => clk,
            rst_n              => rst_n,
            flush              => flush,
            alloc_req          => ckpt_alloc_req,
            alloc_rat_table    => current_rat,
            alloc_ready_mask   => current_ready,
            alloc_free_mask    => fl_current_mask,
            alloc_ghr          => current_ghr,
            alloc_tos          => current_tos,
            alloc_id           => ckpt_alloc_id,
            alloc_ready        => ckpt_ready,
            release_req        => commit_is_branch0 or commit_is_branch1,
            release_id         => release_id_i,
            rollback_req       => rollback_valid,
            rollback_id        => rollback_id,
            restore_rat_table  => rb_rat_table,
            restore_ready_mask => rb_ready_mask,
            restore_free_mask  => rb_free_mask,
            restore_ghr        => open,
            restore_tos        => open
        );

    -- 4. Committed RAT (cRAT)
    u_crat : entity work.talos_crat
        port map (
            clk             => clk,
            rst_n           => rst_n,
            commit_val0     => commit_val0,
            commit_rd_arch0 => commit_rd_arch0,
            commit_rd_phys0 => commit_rd_phys0,
            commit_val1     => commit_val1,
            commit_rd_arch1 => commit_rd_arch1,
            commit_rd_phys1 => commit_rd_phys1,
            crat_table_out  => crat_table
        );

    -- Assemble and register output bundle to Dispatch
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            out_bundle_reg <= (others => RENAME_PKT_ZERO);
        elsif rising_edge(clk) then
            if flush = '1' or rollback_valid = '1' then
                out_bundle_reg <= (others => RENAME_PKT_ZERO);
            elsif stall = '0' then
                -- Way 0
                if decode_bundle(0).valid = '1' then
                    out_bundle_reg(0).valid       <= '1';
                    out_bundle_reg(0).pc          <= decode_bundle(0).pc;
                    out_bundle_reg(0).fu_type     <= decode_bundle(0).fu_type;
                    out_bundle_reg(0).alu_op      <= decode_bundle(0).alu_op;
                    out_bundle_reg(0).br_op       <= decode_bundle(0).br_op;
                    out_bundle_reg(0).md_op       <= decode_bundle(0).md_op;
                    out_bundle_reg(0).mem_op      <= decode_bundle(0).mem_op;
                    out_bundle_reg(0).fpu_op      <= decode_bundle(0).fpu_op;
                    out_bundle_reg(0).rs1_phys    <= rs1_phys0;
                    out_bundle_reg(0).rs1_ready   <= rs1_ready0;
                    out_bundle_reg(0).rs2_phys    <= rs2_phys0;
                    out_bundle_reg(0).rs2_ready   <= rs2_ready0;
                    out_bundle_reg(0).rs3_phys    <= (others => '0');
                    out_bundle_reg(0).rs3_ready   <= '1';
                    out_bundle_reg(0).rd_phys     <= alloc_tag0 when decode_bundle(0).has_dest = '1' else (others => '0');
                    out_bundle_reg(0).rd_arch     <= decode_bundle(0).rd_arch;
                    out_bundle_reg(0).old_rd_phys <= old_rd_phys0;
                    out_bundle_reg(0).has_dest    <= decode_bundle(0).has_dest;
                    out_bundle_reg(0).imm         <= decode_bundle(0).imm;
                    out_bundle_reg(0).use_imm     <= decode_bundle(0).use_imm;
                    out_bundle_reg(0).rob_idx     <= (others => '0'); -- Assigned at dispatch
                    out_bundle_reg(0).lsq_idx     <= (others => '0'); -- Assigned at dispatch
                    out_bundle_reg(0).ckpt_id     <= ckpt_alloc_id;
                    out_bundle_reg(0).is_branch   <= decode_bundle(0).is_branch;
                    out_bundle_reg(0).is_jump     <= decode_bundle(0).is_jump;
                    out_bundle_reg(0).is_load     <= decode_bundle(0).is_load;
                    out_bundle_reg(0).is_store    <= decode_bundle(0).is_store;
                    out_bundle_reg(0).is_csr      <= decode_bundle(0).is_csr;
                    out_bundle_reg(0).pred_taken  <= decode_bundle(0).pred_taken;
                    out_bundle_reg(0).pred_target <= decode_bundle(0).pred_target;
                    out_bundle_reg(0).illegal_op  <= decode_bundle(0).illegal_op;
                else
                    out_bundle_reg(0) <= RENAME_PKT_ZERO;
                end if;

                -- Way 1
                if decode_bundle(1).valid = '1' then
                    out_bundle_reg(1).valid       <= '1';
                    out_bundle_reg(1).pc          <= decode_bundle(1).pc;
                    out_bundle_reg(1).fu_type     <= decode_bundle(1).fu_type;
                    out_bundle_reg(1).alu_op      <= decode_bundle(1).alu_op;
                    out_bundle_reg(1).br_op       <= decode_bundle(1).br_op;
                    out_bundle_reg(1).md_op       <= decode_bundle(1).md_op;
                    out_bundle_reg(1).mem_op      <= decode_bundle(1).mem_op;
                    out_bundle_reg(1).fpu_op      <= decode_bundle(1).fpu_op;
                    out_bundle_reg(1).rs1_phys    <= rs1_phys1;
                    out_bundle_reg(1).rs1_ready   <= rs1_ready1;
                    out_bundle_reg(1).rs2_phys    <= rs2_phys1;
                    out_bundle_reg(1).rs2_ready   <= rs2_ready1;
                    out_bundle_reg(1).rs3_phys    <= (others => '0');
                    out_bundle_reg(1).rs3_ready   <= '1';
                    out_bundle_reg(1).rd_phys     <= alloc_tag1 when decode_bundle(1).has_dest = '1' else (others => '0');
                    out_bundle_reg(1).rd_arch     <= decode_bundle(1).rd_arch;
                    out_bundle_reg(1).old_rd_phys <= old_rd_phys1;
                    out_bundle_reg(1).has_dest    <= decode_bundle(1).has_dest;
                    out_bundle_reg(1).imm         <= decode_bundle(1).imm;
                    out_bundle_reg(1).use_imm     <= decode_bundle(1).use_imm;
                    out_bundle_reg(1).rob_idx     <= (others => '0');
                    out_bundle_reg(1).lsq_idx     <= (others => '0');
                    out_bundle_reg(1).ckpt_id     <= ckpt_alloc_id;
                    out_bundle_reg(1).is_branch   <= decode_bundle(1).is_branch;
                    out_bundle_reg(1).is_jump     <= decode_bundle(1).is_jump;
                    out_bundle_reg(1).is_load     <= decode_bundle(1).is_load;
                    out_bundle_reg(1).is_store    <= decode_bundle(1).is_store;
                    out_bundle_reg(1).is_csr      <= decode_bundle(1).is_csr;
                    out_bundle_reg(1).pred_taken  <= decode_bundle(1).pred_taken;
                    out_bundle_reg(1).pred_target <= decode_bundle(1).pred_target;
                    out_bundle_reg(1).illegal_op  <= decode_bundle(1).illegal_op;
                else
                    out_bundle_reg(1) <= RENAME_PKT_ZERO;
                end if;
            end if;
        end if;
    end process;

    rename_bundle <= out_bundle_reg;

end architecture rtl;
