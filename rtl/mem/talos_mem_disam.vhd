-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Memory: Memory Disambiguation and Speculative Violation Replay Monitor
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_mem_disam is
    generic (
        LQ_ENTRIES : integer := LQ_DEPTH
    );
    port (
        -- Ingress Store Address Resolution
        store_val        : in  std_logic;
        store_addr       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        store_mask       : in  std_logic_vector(3 downto 0);
        store_rob_idx    : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);

        -- Load Queue Snooping Inputs (Array of in-flight executed loads)
        lq_valid         : in  std_logic_vector(LQ_ENTRIES-1 downto 0);
        lq_executed      : in  std_logic_vector(LQ_ENTRIES-1 downto 0);
        lq_rob_idx_array : in  std_logic_vector(LQ_ENTRIES*ROB_INDEX_BITS-1 downto 0);
        lq_addr_array    : in  std_logic_vector(LQ_ENTRIES*ADDR_WIDTH-1 downto 0);
        lq_mask_array    : in  std_logic_vector(LQ_ENTRIES*4-1 downto 0);

        -- Memory Violation Outputs to ROB
        violation_detected : out std_logic;
        violation_rob_idx  : out std_logic_vector(ROB_INDEX_BITS-1 downto 0)
    );
end entity talos_mem_disam;

architecture rtl of talos_mem_disam is
begin

    process(store_val, store_addr, store_mask, store_rob_idx,
            lq_valid, lq_executed, lq_rob_idx_array, lq_addr_array, lq_mask_array)
        variable viol     : boolean;
        variable v_rob    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        variable cur_rob  : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        variable cur_addr : std_logic_vector(ADDR_WIDTH-1 downto 0);
        variable cur_mask : std_logic_vector(3 downto 0);
        variable byte_col : boolean;
    begin
        viol  := false;
        v_rob := (others => '0');

        if store_val = '1' then
            for i in 0 to LQ_ENTRIES-1 loop
                if lq_valid(i) = '1' and lq_executed(i) = '1' and not viol then
                    cur_rob  := lq_rob_idx_array((i+1)*ROB_INDEX_BITS-1 downto i*ROB_INDEX_BITS);
                    cur_addr := lq_addr_array((i+1)*ADDR_WIDTH-1 downto i*ADDR_WIDTH);
                    cur_mask := lq_mask_array((i+1)*4-1 downto i*4);

                    -- Check if load is younger than store in program order
                    if unsigned(cur_rob) > unsigned(store_rob_idx) then
                        -- Check word address match
                        if cur_addr(ADDR_WIDTH-1 downto 2) = store_addr(ADDR_WIDTH-1 downto 2) then
                            -- Check byte lane overlap
                            byte_col := false;
                            for b in 0 to 3 loop
                                if cur_mask(b) = '1' and store_mask(b) = '1' then
                                    byte_col := true;
                                end if;
                            end loop;

                            if byte_col then
                                viol  := true;
                                v_rob := cur_rob;
                            end if;
                        end if;
                    end if;
                end if;
            end loop;
        end if;

        violation_detected <= bool_to_sl(viol);
        violation_rob_idx  <= v_rob;
    end process;

end architecture rtl;
