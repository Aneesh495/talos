-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Commit: 32-Entry Circular Reorder Buffer (ROB) with Precise Exception Recovery
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_rob is
    generic (
        DEPTH      : integer := ROB_DEPTH;      -- 32 entries
        INDEX_BITS : integer := ROB_INDEX_BITS  -- 5 bits
    );
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;
        flush               : in  std_logic;

        -- Allocation Interface from Dispatch (Tail)
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
        alloc_idx0_out      : out std_logic_vector(INDEX_BITS-1 downto 0);
        alloc_idx1_out      : out std_logic_vector(INDEX_BITS-1 downto 0);

        -- CDB Completion Snooping
        cdb_bus             : in  cdb_bus_t;

        -- Branch Unit Resolution
        branch_resolved     : in  std_logic;
        branch_rob_idx      : in  std_logic_vector(INDEX_BITS-1 downto 0);
        branch_mispred      : in  std_logic;
        branch_target_pc    : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- In-Order Retirement Interface to Free List & cRAT (Head)
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

        -- Pipeline Trap / Exception Redirect
        trap_val            : out std_logic;
        trap_pc             : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        trap_cause          : out std_logic_vector(4 downto 0);
        trap_epc            : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Branch Misprediction Redirect
        mispred_val         : out std_logic;
        mispred_pc          : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        mispred_ckpt_id     : out std_logic_vector(CKPT_ID_BITS-1 downto 0)
    );
end entity talos_rob;

architecture rtl of talos_rob is

    type rob_entry_internal_t is record
        valid        : std_logic;
        complete     : std_logic;
        pc           : std_logic_vector(ADDR_WIDTH-1 downto 0);
        rd_arch      : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rd_phys      : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        old_rd_phys  : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        has_dest     : std_logic;
        is_store     : std_logic;
        is_branch    : std_logic;
        ckpt_id      : std_logic_vector(CKPT_ID_BITS-1 downto 0);
        mispredicted : std_logic;
        target_pc    : std_logic_vector(ADDR_WIDTH-1 downto 0);
        exception    : std_logic;
        exc_cause    : std_logic_vector(4 downto 0);
    end record rob_entry_internal_t;

    type rob_array_t is array (0 to DEPTH-1) of rob_entry_internal_t;
    signal rob : rob_array_t := (others => (
        valid        => '0',
        complete     => '0',
        pc           => (others => '0'),
        rd_arch      => (others => '0'),
        rd_phys      => (others => '0'),
        old_rd_phys  => (others => '0'),
        has_dest     => '0',
        is_store     => '0',
        is_branch    => '0',
        ckpt_id      => (others => '0'),
        mispredicted => '0',
        target_pc    => (others => '0'),
        exception    => '0',
        exc_cause    => (others => '0')
    ));

    signal head_ptr   : integer range 0 to DEPTH-1 := 0;
    signal tail_ptr   : integer range 0 to DEPTH-1 := 0;
    signal count_reg  : integer range 0 to DEPTH   := 0;

begin

    rob_has_space1 <= '1' when count_reg <= DEPTH - 1 else '0';
    rob_has_space2 <= '1' when count_reg <= DEPTH - 2 else '0';

    alloc_idx0_out <= std_logic_vector(to_unsigned(tail_ptr, INDEX_BITS));
    alloc_idx1_out <= std_logic_vector(to_unsigned((tail_ptr + 1) mod DEPTH, INDEX_BITS));

    -- In-Order Retirement and Exception Process
    process(clk, rst_n)
        variable next_rob   : rob_array_t;
        variable cur_head   : integer range 0 to DEPTH-1;
        variable cur_tail   : integer range 0 to DEPTH-1;
        variable cur_count  : integer range 0 to DEPTH;
        variable cdb_idx    : integer range 0 to DEPTH-1;
        variable h0, h1     : integer range 0 to DEPTH-1;
        variable commit0_ok : boolean;
        variable commit1_ok : boolean;
    begin
        if rst_n = '0' then
            for i in 0 to DEPTH-1 loop
                rob(i).valid <= '0';
            end loop;
            head_ptr          <= 0;
            tail_ptr          <= 0;
            count_reg         <= 0;
            commit_val0       <= '0';
            commit_rd_arch0   <= (others => '0');
            commit_rd_phys0   <= (others => '0');
            commit_old_phys0  <= (others => '0');
            commit_is_store0  <= '0';
            commit_is_branch0 <= '0';
            commit_ckpt_id0   <= (others => '0');
            commit_val1       <= '0';
            commit_rd_arch1   <= (others => '0');
            commit_rd_phys1   <= (others => '0');
            commit_old_phys1  <= (others => '0');
            commit_is_store1  <= '0';
            commit_is_branch1 <= '0';
            commit_ckpt_id1   <= (others => '0');
            trap_val          <= '0';
            trap_pc           <= (others => '0');
            trap_cause        <= (others => '0');
            trap_epc          <= (others => '0');
            mispred_val       <= '0';
            mispred_pc        <= (others => '0');
            mispred_ckpt_id   <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                for i in 0 to DEPTH-1 loop
                    rob(i).valid <= '0';
                end loop;
                head_ptr    <= 0;
                tail_ptr    <= 0;
                count_reg   <= 0;
                commit_val0 <= '0';
                commit_val1 <= '0';
                trap_val    <= '0';
                mispred_val <= '0';
            else
                next_rob    := rob;
                cur_head    := head_ptr;
                cur_tail    := tail_ptr;
                cur_count   := count_reg;
                commit_val0 <= '0';
                commit_val1 <= '0';
                trap_val    <= '0';
                mispred_val <= '0';

                -- 1. SNOOP CDB: Record instruction completion and exceptions
                for c in 0 to CDB_CHANNELS-1 loop
                    if cdb_bus(c).valid = '1' then
                        cdb_idx := to_integer(unsigned(cdb_bus(c).rob_idx));
                        if next_rob(cdb_idx).valid = '1' then
                            next_rob(cdb_idx).complete  := '1';
                            next_rob(cdb_idx).exception := cdb_bus(c).exception;
                            next_rob(cdb_idx).exc_cause := cdb_bus(c).exc_cause;
                        end if;
                    end if;
                end loop;

                -- 2. RECORD BRANCH UNIT RESOLUTIONS
                if branch_resolved = '1' then
                    cdb_idx := to_integer(unsigned(branch_rob_idx));
                    if next_rob(cdb_idx).valid = '1' then
                        next_rob(cdb_idx).complete     := '1';
                        next_rob(cdb_idx).mispredicted := branch_mispred;
                        next_rob(cdb_idx).target_pc    := branch_target_pc;
                    end if;
                end if;

                -- 3. ALLOCATE NEW INCOMING INSTRUCTIONS FROM DISPATCH
                if alloc_val0 = '1' and cur_count < DEPTH then
                    next_rob(cur_tail).valid        := '1';
                    next_rob(cur_tail).complete     := '0';
                    next_rob(cur_tail).pc           := alloc_pc0;
                    next_rob(cur_tail).rd_arch      := alloc_rd_arch0;
                    next_rob(cur_tail).rd_phys      := alloc_rd_phys0;
                    next_rob(cur_tail).old_rd_phys  := alloc_old_phys0;
                    next_rob(cur_tail).has_dest     := alloc_has_dest0;
                    next_rob(cur_tail).is_store     := alloc_is_store0;
                    next_rob(cur_tail).is_branch    := alloc_is_branch0;
                    next_rob(cur_tail).ckpt_id      := alloc_ckpt_id0;
                    next_rob(cur_tail).mispredicted := '0';
                    next_rob(cur_tail).exception    := '0';
                    cur_tail := (cur_tail + 1) mod DEPTH;
                    cur_count := cur_count + 1;
                end if;

                if alloc_val1 = '1' and cur_count < DEPTH then
                    next_rob(cur_tail).valid        := '1';
                    next_rob(cur_tail).complete     := '0';
                    next_rob(cur_tail).pc           := alloc_pc1;
                    next_rob(cur_tail).rd_arch      := alloc_rd_arch1;
                    next_rob(cur_tail).rd_phys      := alloc_rd_phys1;
                    next_rob(cur_tail).old_rd_phys  := alloc_old_phys1;
                    next_rob(cur_tail).has_dest     := alloc_has_dest1;
                    next_rob(cur_tail).is_store     := alloc_is_store1;
                    next_rob(cur_tail).is_branch    := alloc_is_branch1;
                    next_rob(cur_tail).ckpt_id      := alloc_ckpt_id1;
                    next_rob(cur_tail).mispredicted := '0';
                    next_rob(cur_tail).exception    := '0';
                    cur_tail := (cur_tail + 1) mod DEPTH;
                    cur_count := cur_count + 1;
                end if;

                -- 4. IN-ORDER COMMIT EVALUATION (HEAD)
                h0 := cur_head;
                h1 := (cur_head + 1) mod DEPTH;

                commit0_ok := false;
                commit1_ok := false;

                if cur_count >= 1 and next_rob(h0).valid = '1' and next_rob(h0).complete = '1' then
                    -- Check for exception on Head 0
                    if next_rob(h0).exception = '1' then
                        trap_val   <= '1';
                        trap_cause <= next_rob(h0).exc_cause;
                        trap_epc   <= next_rob(h0).pc;
                        trap_pc    <= x"00001004"; -- Trap vector
                        -- Exception halts retirement and flushes pipeline
                    elsif next_rob(h0).mispredicted = '1' then
                        -- Mispredicted branch retirement
                        mispred_val       <= '1';
                        mispred_pc        <= next_rob(h0).target_pc;
                        mispred_ckpt_id   <= next_rob(h0).ckpt_id;
                        commit_val0       <= '1';
                        commit_rd_arch0   <= next_rob(h0).rd_arch;
                        commit_rd_phys0   <= next_rob(h0).rd_phys;
                        commit_old_phys0  <= next_rob(h0).old_rd_phys;
                        commit_is_store0  <= next_rob(h0).is_store;
                        commit_is_branch0 <= next_rob(h0).is_branch;
                        commit_ckpt_id0   <= next_rob(h0).ckpt_id;
                        next_rob(h0).valid := '0';
                        cur_head  := (cur_head + 1) mod DEPTH;
                        cur_count := cur_count - 1;
                    else
                        -- Successful architectural commit of Head 0
                        commit0_ok        := true;
                        commit_val0       <= '1';
                        commit_rd_arch0   <= next_rob(h0).rd_arch;
                        commit_rd_phys0   <= next_rob(h0).rd_phys;
                        commit_old_phys0  <= next_rob(h0).old_rd_phys;
                        commit_is_store0  <= next_rob(h0).is_store;
                        commit_is_branch0 <= next_rob(h0).is_branch;
                        commit_ckpt_id0   <= next_rob(h0).ckpt_id;
                        next_rob(h0).valid := '0';
                        cur_head  := (cur_head + 1) mod DEPTH;
                        cur_count := cur_count - 1;

                        -- Check Head 1 commit in parallel
                        if cur_count >= 1 and next_rob(h1).valid = '1' and next_rob(h1).complete = '1' and
                           next_rob(h1).exception = '0' and next_rob(h1).mispredicted = '0' then
                            commit1_ok        := true;
                            commit_val1       <= '1';
                            commit_rd_arch1   <= next_rob(h1).rd_arch;
                            commit_rd_phys1   <= next_rob(h1).rd_phys;
                            commit_old_phys1  <= next_rob(h1).old_rd_phys;
                            commit_is_store1  <= next_rob(h1).is_store;
                            commit_is_branch1 <= next_rob(h1).is_branch;
                            commit_ckpt_id1   <= next_rob(h1).ckpt_id;
                            next_rob(h1).valid := '0';
                            cur_head  := (cur_head + 1) mod DEPTH;
                            cur_count := cur_count - 1;
                        end if;
                    end if;
                end if;

                rob       <= next_rob;
                head_ptr  <= cur_head;
                tail_ptr  <= cur_tail;
                count_reg <= cur_count;
            end if;
        end if;
    end process;

end architecture rtl;
