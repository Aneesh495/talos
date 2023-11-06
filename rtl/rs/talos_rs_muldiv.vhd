-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Reservation Station: 4-Entry Dedicated RS for Hardware Multiplier / Divider
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_rs_muldiv is
    generic (
        DEPTH : integer := RS_MULDIV_DEPTH -- 4 entries
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        flush      : in  std_logic;

        -- Allocation from Dispatch
        push_val   : in  std_logic;
        push_pkt   : in  rename_pkt_t;
        rs_ready   : out std_logic;

        -- CDB Snooping (Dynamic Wakeup)
        cdb_bus    : in  cdb_bus_t;

        -- Issue Port to Multiplier / Divider
        issue_val  : out std_logic;
        issue_pkt  : out rename_pkt_t
    );
end entity talos_rs_muldiv;

architecture rtl of talos_rs_muldiv is

    type rs_array_t is array (0 to DEPTH-1) of rename_pkt_t;
    signal rs_entries : rs_array_t := (others => RENAME_PKT_ZERO);

    signal free_slots : integer range 0 to DEPTH;

    signal ready_to_issue : std_logic_vector(DEPTH-1 downto 0);
    signal sel_idx        : integer range 0 to DEPTH-1;
    signal found_iss      : boolean;

begin

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

    rs_ready <= '1' when free_slots >= 1 else '0';

    -- Evaluate readiness
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

    -- Select oldest ready entry
    process(ready_to_issue, rs_entries)
        variable f   : boolean;
        variable idx : integer range 0 to DEPTH-1;
    begin
        f   := false;
        idx := 0;
        for i in 0 to DEPTH-1 loop
            if ready_to_issue(i) = '1' and not f then
                idx := i;
                f   := true;
            end if;
        end loop;
        sel_idx   <= idx;
        found_iss <= f;
    end process;

    issue_val <= bool_to_sl(found_iss);
    issue_pkt <= rs_entries(sel_idx);

    -- State management process
    process(clk, rst_n)
        variable next_entries : rs_array_t;
        variable allocated    : boolean;
    begin
        if rst_n = '0' then
            rs_entries <= (others => RENAME_PKT_ZERO);
        elsif rising_edge(clk) then
            if flush = '1' then
                rs_entries <= (others => RENAME_PKT_ZERO);
            else
                next_entries := rs_entries;

                -- 1. SNOOP CDB FOR WAKEUP
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

                -- 2. CLEAR ISSUED ENTRY
                if found_iss then
                    next_entries(sel_idx).valid := '0';
                end if;

                -- 3. ALLOCATE NEW INCOMING INSTRUCTION
                allocated := false;
                if push_val = '1' then
                    for i in 0 to DEPTH-1 loop
                        if next_entries(i).valid = '0' and not allocated then
                            next_entries(i) := push_pkt;
                            for c in 0 to CDB_CHANNELS-1 loop
                                if cdb_bus(c).valid = '1' and to_integer(unsigned(cdb_bus(c).phys_tag)) /= 0 then
                                    if push_pkt.rs1_ready = '0' and push_pkt.rs1_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs1_ready := '1';
                                    end if;
                                    if push_pkt.rs2_ready = '0' and push_pkt.rs2_phys = cdb_bus(c).phys_tag then
                                        next_entries(i).rs2_ready := '1';
                                    end if;
                                end if;
                            end loop;
                            allocated := true;
                        end if;
                    end loop;
                end if;

                rs_entries <= next_entries;
            end if;
        end if;
    end process;

end architecture rtl;
