-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Decode: Dual-Issue Decode Stage with Intra-Bundle Hazard Detection
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_decode_stage is
    port (
        clk              : in  std_logic;
        rst_n            : in  std_logic;
        flush            : in  std_logic;
        stall            : in  std_logic;

        -- Ingress from Fetch Buffer
        fetch_bundle     : in  fetch_bundle_t;
        fetch_empty      : in  std_logic;
        decode_pop_count : out integer range 0 to FETCH_WIDTH;

        -- Egress to Rename Stage
        decode_bundle    : out decode_bundle_t
    );
end entity talos_decode_stage;

architecture rtl of talos_decode_stage is

    signal raw_dec0 : decode_pkt_t;
    signal raw_dec1 : decode_pkt_t;

    signal stage_bundle_reg : decode_bundle_t := (others => DECODE_PKT_ZERO);
    signal pop_count_i      : integer range 0 to FETCH_WIDTH;

begin

    -- Instantiate parallel decoders for Way 0 and Way 1
    u_dec0 : entity work.talos_decoder
        port map (
            instr_valid => fetch_bundle(0).valid and not fetch_empty,
            pc          => fetch_bundle(0).pc,
            instr       => fetch_bundle(0).instr,
            pred_taken  => fetch_bundle(0).pred_taken,
            pred_target => fetch_bundle(0).pred_target,
            dec_pkt     => raw_dec0
        );

    u_dec1 : entity work.talos_decoder
        port map (
            instr_valid => fetch_bundle(1).valid and not fetch_empty,
            pc          => fetch_bundle(1).pc,
            instr       => fetch_bundle(1).instr,
            pred_taken  => fetch_bundle(1).pred_taken,
            pred_target => fetch_bundle(1).pred_target,
            dec_pkt     => raw_dec1
        );

    -- Intra-bundle hazard arbitration
    process(raw_dec0, raw_dec1, fetch_bundle, fetch_empty, stall)
    begin
        if stall = '1' or fetch_empty = '1' then
            pop_count_i <= 0;
        elsif raw_dec0.valid = '0' then
            pop_count_i <= 0;
        elsif raw_dec0.is_branch = '1' or raw_dec0.is_jump = '1' or raw_dec0.is_csr = '1' then
            -- Branch, Jump, or CSR serializes execution: only consume Way 0
            pop_count_i <= 1;
        elsif raw_dec1.valid = '1' then
            pop_count_i <= 2;
        else
            pop_count_i <= 1;
        end if;
    end process;

    decode_pop_count <= pop_count_i;

    -- Pipeline register driving Rename stage
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            stage_bundle_reg <= (others => DECODE_PKT_ZERO);
        elsif rising_edge(clk) then
            if flush = '1' then
                stage_bundle_reg <= (others => DECODE_PKT_ZERO);
            elsif stall = '0' then
                if pop_count_i >= 1 then
                    stage_bundle_reg(0) <= raw_dec0;
                else
                    stage_bundle_reg(0) <= DECODE_PKT_ZERO;
                end if;

                if pop_count_i = 2 then
                    stage_bundle_reg(1) <= raw_dec1;
                else
                    stage_bundle_reg(1) <= DECODE_PKT_ZERO;
                end if;
            end if;
        end if;
    end process;

    decode_bundle <= stage_bundle_reg;

end architecture rtl;
