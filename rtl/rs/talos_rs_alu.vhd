-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Reservation Station: 8-Entry Unified RS for ALU0, ALU1, and Branch Units
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_rs_alu is
    generic (
        DEPTH : integer := RS_ALU_DEPTH -- 8 entries
    );
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;
        flush          : in  std_logic;

        -- Allocation from Dispatch
        push_val0      : in  std_logic;
        push_pkt0      : in  rename_pkt_t;
        push_val1      : in  std_logic;
        push_pkt1      : in  rename_pkt_t;
        rs_ready       : out std_logic;

        -- CDB Snooping (Dynamic Wakeup)
        cdb_bus        : in  cdb_bus_t;

        -- Issue Port 0 (ALU0 / Branch Unit)
        issue_val0     : out std_logic;
        issue_pkt0     : out rename_pkt_t;

        -- Issue Port 1 (ALU1 Unit)
        issue_val1     : out std_logic;
        issue_pkt1     : out rename_pkt_t
    );
end entity talos_rs_alu;

architecture rtl of talos_rs_alu is

    type rs_array_t is array (0 to DEPTH-1) of rename_pkt_t;
    signal rs_entries : rs_array_t := (others => RENAME_PKT_ZERO);

    signal free_slots : integer range 0 to DEPTH;

    signal ready_to_issue : std_logic_vector(DEPTH-1 downto 0);
    signal sel_idx0       : integer range 0 to DEPTH-1;
    signal sel_idx1       : integer range 0 to DEPTH-1;
    signal found_iss0     : boolean;
    signal found_iss1     : boolean;

begin

    -- Free slot counter
    process(rs_entries)
        variable cnt : integer range 0 to DEPTH;
    begin
        cnt := 0;
        for i in 0 to DEPTH-1 loop
            if rs_entries(i).valid = '0' then
                cnt := cnt + 1;
            end if;
        end loop;
        free_slots <= cnt;
    end process;

    rs_ready <= '1' when free_slots >= 2 else '0';

    -- Evaluate readiness of entries for out-of-order execution
    process(rs_entries)
    begin
        for i in 0 to DEPTH-1 loop
            if rs_entries(i).valid = '1' and
               rs_entries(i).rs1_ready = '1' and
               rs_entries(i).rs2_ready = '1' then
                ready_to_issue(i) <= '1';
            else
                ready_to_issue(i) <= '0';
            end if;
        end loop;
    end process;

    -- Select up to 2 ready instructions (oldest / lowest index first)
    process(ready_to_issue, rs_entries)
        variable f0, f1   : boolean;
        variable i0, i1   : integer range 0 to DEPTH-1;
    begin
        f0 := false;
        f1 := false;
        i0 := 0;
        i1 := 0;

        for i in 0 to DEPTH-1 loop
            if ready_to_issue(i) = '1' then
                if not f0 then
                    i0 := i;
                    f0 := true;
                elsif not f1 then
                    -- ALU1 only executes non-branch instructions
                    if rs_entries(i).fu_type /= FU_BRANCH and rs_entries(i).fu_type /= FU_CSR then
                        i1 := i;
                        f1 := true;
                    end if;
                end if;
            end if;
        end loop;

        sel_idx0   <= i0;
        sel_idx1   <= i1;
        found_iss0 <= f0;
        found_iss1 <= f1;
    end process;

    issue_val0 <= bool_to_sl(found_iss0);
    issue_pkt0 <= rs_entries(sel_idx0);

    issue_val1 <= bool_to_sl(found_iss1);
    issue_pkt1 <= rs_entries(sel_idx1);

    -- Reservation Station Storage, Wakeup, Allocation, and Eviction Process
    process(clk, rst_n)
        variable next_entries : rs_array_t;
        variable p0_allocated : boolean;
        variable p1_allocated : boolean;
    begin
        if rst_n = '0' then
            rs_entries <= (others => RENAME_PKT_ZERO);
        elsif rising_edge(clk) then
            if flush = '1' then
                rs_entries <= (others => RENAME_PKT_ZERO);
            else
                next_entries := rs_entries;

                -- 1. SNOOP CDB: Dynamic Wakeup of unready source operands
                for i in 0 to DEPTH-1 loop
                    if next_entries(i).valid = '1' then
                        for c in 0 to CDB_CHANNELS-1 loop
                            if cdb_bus(c).valid = '1' and to_integer(unsigned(cdb_bus(c).phys_tag)) /= 0 then
                                if next_entries(i).rs1_ready = '0' and next_entries(i).rs1_phys = cdb_bus(c).phys_tag then
                                    next_entries(i).rs1_ready := '1';
                                end if;
                                if next_entries(i).rs2_ready = '0' and next_entries(i).rs2_phys = cdb_bus(c).phys_tag then
                                    next_entries(i).rs2_ready := '1';
                                end if;
                            end if;
                        end loop;
                    end if;
                end loop;

                -- 2. CLEAR ISSUED INSTRUCTIONS
                if found_iss0 then
                    next_entries(sel_idx0).valid := '0';
                end if;
                if found_iss1 then
                    next_entries(sel_idx1).valid := '0';
                end if;

                -- 3. ALLOCATE NEW INCOMING INSTRUCTIONS FROM DISPATCH
                p0_allocated := false;
                p1_allocated := false;

                if push_val0 = '1' then
                    for i in 0 to DEPTH-1 loop
                        if next_entries(i).valid = '0' and not p0_allocated then
                            next_entries(i) := push_pkt0;
                            -- Immediate bypass check against concurrent CDB broadcasts
                            for c in 0 to CDB_CHANNELS-1 loop
                                if cdb_bus(c).valid = '1' and to_integer(unsigned(cdb_bus(c).phys_tag)) /= 0 then
                                    if push_pkt0.rs1_ready = '0' and push_pkt0.rs1_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs1_ready := '1';
                                    end if;
                                    if push_pkt0.rs2_ready = '0' and push_pkt0.rs2_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs2_ready := '1';
                                    end if;
                                end if;
                            end loop;
                            p0_allocated := true;
                        end if;
                    end loop;
                end if;

                if push_val1 = '1' then
                    for i in 0 to DEPTH-1 loop
                        if next_entries(i).valid = '0' and not p1_allocated then
                            next_entries(i) := push_pkt1;
                            for c in 0 to CDB_CHANNELS-1 loop
                                if cdb_bus(c).valid = '1' and to_integer(unsigned(cdb_bus(c).phys_tag)) /= 0 then
                                    if push_pkt1.rs1_ready = '0' and push_pkt1.rs1_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs1_ready := '1';
                                    end if;
                                    if push_pkt1.rs2_ready = '0' and push_pkt1.rs2_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs2_ready := '1';
                                    end if;
                                end if;
                            end loop;
                            p1_allocated := true;
                        end if;
                    end loop;
                end if;

                rs_entries <= next_entries;
            end if;
        end if;
    end process;

end architecture rtl;
