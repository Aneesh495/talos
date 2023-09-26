-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Front-End: Gshare Directional Branch Predictor with Speculative History Repair
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_bpred_gshare is
    generic (
        GHR_BITS   : integer := 10;
        PHT_ENTRIES: integer := 1024
    );
    port (
        clk                 : in  std_logic;
        rst_n               : in  std_logic;

        -- Query Interface (Fetch Stage)
        fetch_pc            : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        pred_taken          : out std_logic;
        spec_ghr_out        : out std_logic_vector(GHR_BITS-1 downto 0);

        -- Speculative Fetch Advance
        fetch_advance       : in  std_logic;
        fetch_pred_taken    : in  std_logic;

        -- Resolution and Repair Interface (Execution / Branch Unit)
        resolve_valid       : in  std_logic;
        resolve_pc          : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        resolve_ghr         : in  std_logic_vector(GHR_BITS-1 downto 0);
        resolve_taken       : in  std_logic;
        resolve_mispred     : in  std_logic
    );
end entity talos_bpred_gshare;

architecture rtl of talos_bpred_gshare is

    type pht_table_t is array (0 to PHT_ENTRIES-1) of std_logic_vector(1 downto 0);
    signal pht : pht_table_t := (others => "10"); -- Initialize to weakly taken

    signal ghr_reg : std_logic_vector(GHR_BITS-1 downto 0) := (others => '0');

    signal query_idx   : integer range 0 to PHT_ENTRIES-1;
    signal resolve_idx : integer range 0 to PHT_ENTRIES-1;

begin

    -- Gshare hash: PC xor GHR
    process(fetch_pc, ghr_reg)
        variable pc_slice : std_logic_vector(GHR_BITS-1 downto 0);
    begin
        pc_slice := fetch_pc(GHR_BITS+1 downto 2);
        query_idx <= to_integer(unsigned(pc_slice xor ghr_reg));
    end process;

    -- Prediction is taken if MSB of 2-bit counter is '1' ("10" or "11")
    pred_taken   <= pht(query_idx)(1);
    spec_ghr_out <= ghr_reg;

    -- Resolution index calculation
    process(resolve_pc, resolve_ghr)
        variable pc_slice : std_logic_vector(GHR_BITS-1 downto 0);
    begin
        pc_slice := resolve_pc(GHR_BITS+1 downto 2);
        resolve_idx <= to_integer(unsigned(pc_slice xor resolve_ghr));
    end process;

    -- Global History Register and PHT Update Process
    process(clk, rst_n)
        variable current_counter : std_logic_vector(1 downto 0);
        variable next_counter    : std_logic_vector(1 downto 0);
    begin
        if rst_n = '0' then
            ghr_reg <= (others => '0');
            pht     <= (others => "10");
        elsif rising_edge(clk) then
            -- 1. PHT Update
            if resolve_valid = '1' then
                current_counter := pht(resolve_idx);
                if resolve_taken = '1' then
                    -- Increment with saturation at "11"
                    case current_counter is
                        when "00" => next_counter := "01";
                        when "01" => next_counter := "10";
                        when "10" => next_counter := "11";
                        when "11" => next_counter := "11";
                        when others => next_counter := "10";
                    end case;
                else
                    -- Decrement with saturation at "00"
                    case current_counter is
                        when "11" => next_counter := "10";
                        when "10" => next_counter := "01";
                        when "01" => next_counter := "00";
                        when "00" => next_counter := "00";
                        when others => next_counter := "01";
                    end case;
                end if;
                pht(resolve_idx) <= next_counter;
            end if;

            -- 2. GHR Update with Misprediction Repair
            if resolve_mispred = '1' then
                -- Repair GHR using resolved branch state
                ghr_reg <= resolve_ghr(GHR_BITS-2 downto 0) & resolve_taken;
            elsif fetch_advance = '1' then
                -- Speculatively shift in predicted direction
                ghr_reg <= ghr_reg(GHR_BITS-2 downto 0) & fetch_pred_taken;
            end if;
        end if;
    end process;

end architecture rtl;
