-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Rename: 8-Entry Speculative Checkpoint Store for Single-Cycle Branch Rollback
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_checkpoint is
    generic (
        CKPT_ENTRIES : integer := 8;
        ID_BITS      : integer := 3;
        TABLE_BITS   : integer := ARCH_REG_COUNT * PHYS_REG_BITS; -- 32 * 6 = 192
        PREGS        : integer := PHYS_REG_COUNT;                -- 64
        GHR_BITS     : integer := 10;
        TOS_BITS     : integer := 4
    );
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;
        flush             : in  std_logic;

        -- Allocation Interface (on Branch Rename)
        alloc_req         : in  std_logic;
        alloc_rat_table   : in  std_logic_vector(TABLE_BITS-1 downto 0);
        alloc_ready_mask  : in  std_logic_vector(PREGS-1 downto 0);
        alloc_free_mask   : in  std_logic_vector(PREGS-1 downto 0);
        alloc_ghr         : in  std_logic_vector(GHR_BITS-1 downto 0);
        alloc_tos         : in  std_logic_vector(TOS_BITS-1 downto 0);

        alloc_id          : out std_logic_vector(ID_BITS-1 downto 0);
        alloc_ready       : out std_logic;

        -- Release Interface (on In-Order Commit of Correct Branch)
        release_req       : in  std_logic;
        release_id        : in  std_logic_vector(ID_BITS-1 downto 0);

        -- Rollback Interface (on Misprediction Resolution)
        rollback_req      : in  std_logic;
        rollback_id       : in  std_logic_vector(ID_BITS-1 downto 0);

        restore_rat_table : out std_logic_vector(TABLE_BITS-1 downto 0);
        restore_ready_mask: out std_logic_vector(PREGS-1 downto 0);
        restore_free_mask : out std_logic_vector(PREGS-1 downto 0);
        restore_ghr       : out std_logic_vector(GHR_BITS-1 downto 0);
        restore_tos       : out std_logic_vector(TOS_BITS-1 downto 0)
    );
end entity talos_checkpoint;

architecture rtl of talos_checkpoint is

    type ckpt_entry_t is record
        valid      : std_logic;
        rat_table  : std_logic_vector(TABLE_BITS-1 downto 0);
        ready_mask : std_logic_vector(PREGS-1 downto 0);
        free_mask  : std_logic_vector(PREGS-1 downto 0);
        ghr        : std_logic_vector(GHR_BITS-1 downto 0);
        tos        : std_logic_vector(TOS_BITS-1 downto 0);
    end record ckpt_entry_t;

    type ckpt_array_t is array (0 to CKPT_ENTRIES-1) of ckpt_entry_t;
    signal ckpt_store : ckpt_array_t := (others => (
        valid      => '0',
        rat_table  => (others => '0'),
        ready_mask => (others => '0'),
        free_mask  => (others => '0'),
        ghr        => (others => '0'),
        tos        => (others => '0')
    ));

    signal free_id_found : boolean;
    signal free_id_idx   : integer range 0 to CKPT_ENTRIES-1;

begin

    -- Find next free checkpoint slot
    process(ckpt_store)
        variable found : boolean;
        variable idx   : integer range 0 to CKPT_ENTRIES-1;
    begin
        found := false;
        idx   := 0;
        for i in 0 to CKPT_ENTRIES-1 loop
            if ckpt_store(i).valid = '0' and not found then
                idx   := i;
                found := true;
            end if;
        end loop;

        free_id_found <= found;
        free_id_idx   <= idx;
    end process;

    alloc_id    <= std_logic_vector(to_unsigned(free_id_idx, ID_BITS));
    alloc_ready <= bool_to_sl(free_id_found);

    -- Combinational readout of target checkpoint for rollback
    process(rollback_id, ckpt_store)
        variable target_idx : integer range 0 to CKPT_ENTRIES-1;
    begin
        target_idx := to_integer(unsigned(rollback_id));
        restore_rat_table  <= ckpt_store(target_idx).rat_table;
        restore_ready_mask <= ckpt_store(target_idx).ready_mask;
        restore_free_mask  <= ckpt_store(target_idx).free_mask;
        restore_ghr        <= ckpt_store(target_idx).ghr;
        restore_tos        <= ckpt_store(target_idx).tos;
    end process;

    -- Checkpoint Storage State Machine
    process(clk, rst_n)
        variable rb_idx : integer range 0 to CKPT_ENTRIES-1;
        variable rel_idx: integer range 0 to CKPT_ENTRIES-1;
    begin
        if rst_n = '0' then
            for i in 0 to CKPT_ENTRIES-1 loop
                ckpt_store(i).valid <= '0';
            end loop;
        elsif rising_edge(clk) then
            if flush = '1' then
                for i in 0 to CKPT_ENTRIES-1 loop
                    ckpt_store(i).valid <= '0';
                end loop;
            elsif rollback_req = '1' then
                rb_idx := to_integer(unsigned(rollback_id));
                -- Release the mispredicted checkpoint and invalidate all younger checkpoints
                ckpt_store(rb_idx).valid <= '0';
                for i in 0 to CKPT_ENTRIES-1 loop
                    -- Invalidate all checkpoints allocated after the mispredicted branch
                    if i /= rb_idx then
                        ckpt_store(i).valid <= '0';
                    end if;
                end loop;
            else
                -- Normal allocation
                if alloc_req = '1' and free_id_found then
                    ckpt_store(free_id_idx).valid      <= '1';
                    ckpt_store(free_id_idx).rat_table  <= alloc_rat_table;
                    ckpt_store(free_id_idx).ready_mask <= alloc_ready_mask;
                    ckpt_store(free_id_idx).free_mask  <= alloc_free_mask;
                    ckpt_store(free_id_idx).ghr        <= alloc_ghr;
                    ckpt_store(free_id_idx).tos        <= alloc_tos;
                end if;

                -- Commit release of verified branch
                if release_req = '1' then
                    rel_idx := to_integer(unsigned(release_id));
                    ckpt_store(rel_idx).valid <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
