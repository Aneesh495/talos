-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: Top-Level Integration (PC Gen, BTB, Gshare, RAS, I-Cache, Fetch Buffer)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_axi4_pkg.all;

entity talos_front_top is
    port (
        clk                  : in  std_logic;
        rst_n                : in  std_logic;

        -- Pipeline Control / Redirects
        stall                : in  std_logic;
        flush                : in  std_logic;
        trap_redirect_valid  : in  std_logic;
        trap_redirect_pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        branch_mispred_valid : in  std_logic;
        branch_mispred_pc    : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        restore_tos          : in  std_logic_vector(3 downto 0);

        -- Branch Predictor Resolution
        resolve_valid        : in  std_logic;
        resolve_pc           : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        resolve_target       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        resolve_ghr          : in  std_logic_vector(9 downto 0);
        resolve_taken        : in  std_logic;
        resolve_mispred      : in  std_logic;
        resolve_is_call      : in  std_logic;
        resolve_is_return    : in  std_logic;

        -- Egress Interface to Decode Stage
        decode_pop_count     : in  integer range 0 to FETCH_WIDTH;
        fetch_bundle_out     : out fetch_bundle_t;
        fetch_empty          : out std_logic;

        -- AXI4 Line Refill Interface to System Interconnect
        m_axi_araddr         : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        m_axi_arlen          : out std_logic_vector(7 downto 0);
        m_axi_arsize         : out std_logic_vector(2 downto 0);
        m_axi_arburst        : out std_logic_vector(1 downto 0);
        m_axi_arvalid        : out std_logic;
        m_axi_arready        : in  std_logic;

        m_axi_rdata          : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        m_axi_rresp          : in  std_logic_vector(1 downto 0);
        m_axi_rlast          : in  std_logic;
        m_axi_rvalid         : in  std_logic;
        m_axi_rready         : out std_logic
    );
end entity talos_front_top;

architecture rtl of talos_front_top is

    signal fetch_pc       : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal fetch_pc_next  : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal pc_redirected  : std_logic;

    -- BTB signals
    signal btb_hit        : std_logic;
    signal btb_target     : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal btb_is_call    : std_logic;
    signal btb_is_return  : std_logic;

    -- Gshare predictor signals
    signal gshare_taken   : std_logic;
    signal spec_ghr       : std_logic_vector(9 downto 0);

    -- RAS signals
    signal ras_pop_addr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal ras_pop_valid  : std_logic;
    signal current_tos    : std_logic_vector(3 downto 0);

    -- Branch selection signals
    signal pred_taken     : std_logic;
    signal pred_target    : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- I-Cache signals
    signal icache_ready   : std_logic;
    signal icache_data0   : std_logic_vector(INSTR_WIDTH-1 downto 0);
    signal icache_data1   : std_logic_vector(INSTR_WIDTH-1 downto 0);
    signal icache_valid0  : std_logic;
    signal icache_valid1  : std_logic;

    -- Fetch Buffer signals
    signal buf_in_bundle  : fetch_bundle_t;
    signal buf_almost_full: std_logic;
    signal fetch_stall    : std_logic;

begin

    -- Combined branch prediction decision
    process(btb_hit, btb_target, btb_is_return, ras_pop_addr, ras_pop_valid, gshare_taken)
    begin
        if btb_hit = '1' then
            if btb_is_return = '1' and ras_pop_valid = '1' then
                pred_taken  <= '1';
                pred_target <= ras_pop_addr;
            elsif gshare_taken = '1' then
                pred_taken  <= '1';
                pred_target <= btb_target;
            else
                pred_taken  <= '0';
                pred_target <= (others => '0');
            end if;
        else
            pred_taken  <= '0';
            pred_target <= (others => '0');
        end if;
    end process;

    fetch_stall <= stall or buf_almost_full;

    -- 1. PC Generation
    u_pc_gen : entity work.talos_pc_gen
        port map (
            clk                  => clk,
            rst_n                => rst_n,
            stall                => fetch_stall,
            trap_redirect_valid  => trap_redirect_valid,
            trap_redirect_pc     => trap_redirect_pc,
            branch_mispred_valid => branch_mispred_valid,
            branch_mispred_pc    => branch_mispred_pc,
            pred_taken           => pred_taken,
            pred_target_pc       => pred_target,
            fetch_pc             => fetch_pc,
            fetch_pc_next        => fetch_pc_next,
            pc_redirected        => pc_redirected
        );

    -- 2. Branch Target Buffer
    u_btb : entity work.talos_btb
        port map (
            clk              => clk,
            rst_n            => rst_n,
            fetch_pc         => fetch_pc,
            hit              => btb_hit,
            target_pc        => btb_target,
            is_call          => btb_is_call,
            is_return        => btb_is_return,
            update_valid     => resolve_valid,
            update_pc        => resolve_pc,
            update_target    => resolve_target,
            update_is_call   => resolve_is_call,
            update_is_return => resolve_is_return
        );

    -- 3. Gshare Direction Predictor
    u_gshare : entity work.talos_bpred_gshare
        port map (
            clk              => clk,
            rst_n            => rst_n,
            fetch_pc         => fetch_pc,
            pred_taken       => gshare_taken,
            spec_ghr_out     => spec_ghr,
            fetch_advance    => icache_ready,
            fetch_pred_taken => pred_taken,
            resolve_valid    => resolve_valid,
            resolve_pc       => resolve_pc,
            resolve_ghr      => resolve_ghr,
            resolve_taken    => resolve_taken,
            resolve_mispred  => resolve_mispred
        );

    -- 4. Return Address Stack
    u_ras : entity work.talos_ras
        port map (
            clk           => clk,
            rst_n         => rst_n,
            push_valid    => btb_is_call,
            push_addr     => std_logic_vector(unsigned(fetch_pc) + 4),
            pop_valid     => btb_is_return,
            pop_addr      => ras_pop_addr,
            pop_valid_out => ras_pop_valid,
            current_tos   => current_tos,
            restore_valid => branch_mispred_valid,
            restore_tos   => restore_tos
        );

    -- 5. L1 Instruction Cache
    u_icache : entity work.talos_icache
        port map (
            clk           => clk,
            rst_n         => rst_n,
            flush         => flush,
            fetch_req     => not fetch_stall,
            fetch_addr    => fetch_pc,
            fetch_ready   => icache_ready,
            fetch_data0   => icache_data0,
            fetch_data1   => icache_data1,
            fetch_valid0  => icache_valid0,
            fetch_valid1  => icache_valid1,
            m_axi_araddr  => m_axi_araddr,
            m_axi_arlen   => m_axi_arlen,
            m_axi_arsize  => m_axi_arsize,
            m_axi_arburst => m_axi_arburst,
            m_axi_arvalid => m_axi_arvalid,
            m_axi_arready => m_axi_arready,
            m_axi_rdata   => m_axi_rdata,
            m_axi_rresp   => m_axi_rresp,
            m_axi_rlast   => m_axi_rlast,
            m_axi_rvalid  => m_axi_rvalid,
            m_axi_rready  => m_axi_rready
        );

    -- Assemble bundle for Fetch Buffer
    buf_in_bundle(0).valid       <= icache_valid0 and icache_ready;
    buf_in_bundle(0).pc          <= fetch_pc;
    buf_in_bundle(0).instr       <= icache_data0;
    buf_in_bundle(0).pred_taken  <= pred_taken;
    buf_in_bundle(0).pred_target <= pred_target;
    buf_in_bundle(0).is_rvc      <= '0';

    buf_in_bundle(1).valid       <= icache_valid1 and icache_ready;
    buf_in_bundle(1).pc          <= std_logic_vector(unsigned(fetch_pc) + 4);
    buf_in_bundle(1).instr       <= icache_data1;
    buf_in_bundle(1).pred_taken  <= '0';
    buf_in_bundle(1).pred_target <= (others => '0');
    buf_in_bundle(1).is_rvc      <= '0';

    -- 6. Decoupled Fetch Buffer
    u_fetch_buffer : entity work.talos_fetch_buffer
        port map (
            clk         => clk,
            rst_n       => rst_n,
            flush       => flush or branch_mispred_valid or trap_redirect_valid,
            in_bundle   => buf_in_bundle,
            full        => open,
            almost_full => buf_almost_full,
            pop_count   => decode_pop_count,
            out_bundle  => fetch_bundle_out,
            empty       => fetch_empty
        );

end architecture rtl;
