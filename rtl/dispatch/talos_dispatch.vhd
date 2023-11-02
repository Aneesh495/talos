-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Dispatch: Dual-Issue Dispatch Unit and Structural Hazard Monitor
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_dispatch is
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;
        flush             : in  std_logic;

        -- Ingress from Rename Stage
        rename_bundle     : in  rename_bundle_t;
        stall_rename      : out std_logic;

        -- Structural Readiness from Downstream Queues
        rob_has_space2    : in  std_logic; -- At least 2 slots free in ROB
        rob_has_space1    : in  std_logic; -- At least 1 slot free in ROB
        rob_alloc_idx0    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rob_alloc_idx1    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        rs_alu_ready      : in  std_logic;
        rs_muldiv_ready   : in  std_logic;
        rs_mem_ready      : in  std_logic;
        rs_fpu_ready      : in  std_logic;
        lsq_ready         : in  std_logic;
        lsq_alloc_idx0    : in  std_logic_vector(SQ_INDEX_BITS-1 downto 0);
        lsq_alloc_idx1    : in  std_logic_vector(SQ_INDEX_BITS-1 downto 0);

        -- ROB Allocation Commands
        rob_alloc_val0    : out std_logic;
        rob_alloc_val1    : out std_logic;

        -- LSQ Allocation Commands
        lsq_alloc_val0    : out std_logic;
        lsq_alloc_val1    : out std_logic;

        -- Reservation Station Push Bundles
        rs_alu_push_val0  : out std_logic;
        rs_alu_push_pkt0  : out rename_pkt_t;
        rs_alu_push_val1  : out std_logic;
        rs_alu_push_pkt1  : out rename_pkt_t;

        rs_md_push_val    : out std_logic;
        rs_md_push_pkt    : out rename_pkt_t;

        rs_mem_push_val   : out std_logic;
        rs_mem_push_pkt   : out rename_pkt_t;

        rs_fpu_push_val   : out std_logic;
        rs_fpu_push_pkt   : out rename_pkt_t
    );
end entity talos_dispatch;

architecture rtl of talos_dispatch is

    signal can_dispatch0 : boolean;
    signal can_dispatch1 : boolean;

    signal pkt0_dispatched : rename_pkt_t;
    signal pkt1_dispatched : rename_pkt_t;

begin

    -- Check resource availability for Way 0
    process(rename_bundle, rob_has_space1, rs_alu_ready, rs_muldiv_ready, rs_mem_ready, rs_fpu_ready, lsq_ready)
        variable ok : boolean;
    begin
        ok := false;
        if rename_bundle(0).valid = '1' and rob_has_space1 = '1' then
            case rename_bundle(0).fu_type is
                when FU_ALU0 | FU_ALU1 | FU_BRANCH | FU_CSR =>
                    ok := (rs_alu_ready = '1');
                when FU_MULDIV =>
                    ok := (rs_muldiv_ready = '1');
                when FU_MEM =>
                    ok := (rs_mem_ready = '1' and lsq_ready = '1');
                when FU_FPU =>
                    ok := (rs_fpu_ready = '1');
                when others =>
                    ok := true;
            end case;
        end if;
        can_dispatch0 <= ok;
    end process;

    -- Check resource availability for Way 1
    process(rename_bundle, can_dispatch0, rob_has_space2, rs_alu_ready, rs_muldiv_ready, rs_mem_ready, rs_fpu_ready, lsq_ready)
        variable ok : boolean;
    begin
        ok := false;
        if can_dispatch0 and rename_bundle(1).valid = '1' and rob_has_space2 = '1' then
            case rename_bundle(1).fu_type is
                when FU_ALU0 | FU_ALU1 | FU_BRANCH | FU_CSR =>
                    ok := (rs_alu_ready = '1');
                when FU_MULDIV =>
                    ok := (rs_muldiv_ready = '1');
                when FU_MEM =>
                    ok := (rs_mem_ready = '1' and lsq_ready = '1');
                when FU_FPU =>
                    ok := (rs_fpu_ready = '1');
                when others =>
                    ok := true;
            end case;
        end if;
        can_dispatch1 <= ok;
    end process;

    -- Backpressure Rename stage if Way 0 cannot dispatch, or if Way 1 is valid but cannot dispatch
    stall_rename <= '1' when (rename_bundle(0).valid = '1' and not can_dispatch0) or
                             (rename_bundle(1).valid = '1' and can_dispatch0 and not can_dispatch1) else '0';

    -- Attach allocated ROB and LSQ indices to dispatched packets
    process(rename_bundle, rob_alloc_idx0, lsq_alloc_idx0)
        variable p : rename_pkt_t;
    begin
        p := rename_bundle(0);
        p.rob_idx := rob_alloc_idx0;
        p.lsq_idx := lsq_alloc_idx0;
        pkt0_dispatched <= p;
    end process;

    process(rename_bundle, rob_alloc_idx1, lsq_alloc_idx1)
        variable p : rename_pkt_t;
    begin
        p := rename_bundle(1);
        p.rob_idx := rob_alloc_idx1;
        p.lsq_idx := lsq_alloc_idx1;
        pkt1_dispatched <= p;
    end process;

    -- ROB Allocation Strobes
    rob_alloc_val0 <= bool_to_sl(can_dispatch0);
    rob_alloc_val1 <= bool_to_sl(can_dispatch1);

    -- LSQ Allocation Strobes
    lsq_alloc_val0 <= bool_to_sl(can_dispatch0 and (rename_bundle(0).is_load = '1' or rename_bundle(0).is_store = '1'));
    lsq_alloc_val1 <= bool_to_sl(can_dispatch1 and (rename_bundle(1).is_load = '1' or rename_bundle(1).is_store = '1'));

    -- Steering to Target Functional Unit Reservation Stations
    process(can_dispatch0, can_dispatch1, pkt0_dispatched, pkt1_dispatched, rename_bundle)
    begin
        rs_alu_push_val0 <= '0';
        rs_alu_push_pkt0 <= pkt0_dispatched;
        rs_alu_push_val1 <= '0';
        rs_alu_push_pkt1 <= pkt1_dispatched;

        rs_md_push_val   <= '0';
        rs_md_push_pkt   <= pkt0_dispatched;

        rs_mem_push_val  <= '0';
        rs_mem_push_pkt  <= pkt0_dispatched;

        rs_fpu_push_val  <= '0';
        rs_fpu_push_pkt  <= pkt0_dispatched;

        -- Way 0 Steering
        if can_dispatch0 then
            case rename_bundle(0).fu_type is
                when FU_ALU0 | FU_ALU1 | FU_BRANCH | FU_CSR =>
                    rs_alu_push_val0 <= '1';
                when FU_MULDIV =>
                    rs_md_push_val   <= '1';
                    rs_md_push_pkt   <= pkt0_dispatched;
                when FU_MEM =>
                    rs_mem_push_val  <= '1';
                    rs_mem_push_pkt  <= pkt0_dispatched;
                when FU_FPU =>
                    rs_fpu_push_val  <= '1';
                    rs_fpu_push_pkt  <= pkt0_dispatched;
                when others =>
                    null;
            end case;
        end if;

        -- Way 1 Steering
        if can_dispatch1 then
            case rename_bundle(1).fu_type is
                when FU_ALU0 | FU_ALU1 | FU_BRANCH | FU_CSR =>
                    rs_alu_push_val1 <= '1';
                when FU_MULDIV =>
                    rs_md_push_val   <= '1';
                    rs_md_push_pkt   <= pkt1_dispatched;
                when FU_MEM =>
                    rs_mem_push_val  <= '1';
                    rs_mem_push_pkt  <= pkt1_dispatched;
                when FU_FPU =>
                    rs_fpu_push_val  <= '1';
                    rs_fpu_push_pkt  <= pkt1_dispatched;
                when others =>
                    null;
            end case;
        end if;
    end process;

end architecture rtl;
