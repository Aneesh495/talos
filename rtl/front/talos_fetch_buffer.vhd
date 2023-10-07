-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: Decoupled Dual-Instruction Fetch Queue
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_fetch_buffer is
    generic (
        DEPTH : integer := 8
    );
    port (
        clk            : in  std_logic;
        rst_n          : in  std_logic;
        flush          : in  std_logic;

        -- Ingress Interface (from I-Cache / Predictor)
        in_bundle      : in  fetch_bundle_t;
        full           : out std_logic;
        almost_full    : out std_logic;

        -- Egress Interface (to Decode Stage)
        pop_count      : in  integer range 0 to FETCH_WIDTH;
        out_bundle     : out fetch_bundle_t;
        empty          : out std_logic
    );
end entity talos_fetch_buffer;

architecture rtl of talos_fetch_buffer is

    type queue_array_t is array (0 to DEPTH-1) of fetch_pkt_t;
    signal queue : queue_array_t := (others => FETCH_PKT_ZERO);

    signal wr_ptr  : integer range 0 to DEPTH-1 := 0;
    signal rd_ptr  : integer range 0 to DEPTH-1 := 0;
    signal count   : integer range 0 to DEPTH   := 0;

begin

    full        <= '1' when count >= DEPTH - 1 else '0';
    almost_full <= '1' when count >= DEPTH - 2 else '0';
    empty       <= '1' when count = 0          else '0';

    -- Combinational readout of up to FETCH_WIDTH instructions
    process(queue, rd_ptr, count)
        variable p0, p1 : integer range 0 to DEPTH-1;
    begin
        p0 := rd_ptr;
        if rd_ptr = DEPTH - 1 then
            p1 := 0;
        else
            p1 := rd_ptr + 1;
        end if;

        if count >= 1 then
            out_bundle(0) <= queue(p0);
        else
            out_bundle(0) <= FETCH_PKT_ZERO;
        end if;

        if count >= 2 then
            out_bundle(1) <= queue(p1);
        else
            out_bundle(1) <= FETCH_PKT_ZERO;
        end if;
    end process;

    -- Push and Pop Process
    process(clk, rst_n)
        variable cur_wr   : integer range 0 to DEPTH-1;
        variable cur_rd   : integer range 0 to DEPTH-1;
        variable cur_cnt  : integer range 0 to DEPTH;
        variable num_push : integer range 0 to 2;
    begin
        if rst_n = '0' then
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            queue  <= (others => FETCH_PKT_ZERO);
        elsif rising_edge(clk) then
            if flush = '1' then
                wr_ptr <= 0;
                rd_ptr <= 0;
                count  <= 0;
            else
                cur_wr  := wr_ptr;
                cur_rd  := rd_ptr;
                cur_cnt := count;

                -- 1. Apply pops
                if pop_count > 0 and cur_cnt >= pop_count then
                    cur_rd  := (cur_rd + pop_count) mod DEPTH;
                    cur_cnt := cur_cnt - pop_count;
                end if;

                -- 2. Apply pushes
                num_push := 0;
                if in_bundle(0).valid = '1' and cur_cnt < DEPTH then
                    queue(cur_wr) <= in_bundle(0);
                    cur_wr := (cur_wr + 1) mod DEPTH;
                    cur_cnt := cur_cnt + 1;
                    num_push := num_push + 1;
                end if;

                if in_bundle(1).valid = '1' and cur_cnt < DEPTH then
                    queue(cur_wr) <= in_bundle(1);
                    cur_wr := (cur_wr + 1) mod DEPTH;
                    cur_cnt := cur_cnt + 1;
                    num_push := num_push + 1;
                end if;

                wr_ptr <= cur_wr;
                rd_ptr <= cur_rd;
                count  <= cur_cnt;
            end if;
        end if;
    end process;

end architecture rtl;
