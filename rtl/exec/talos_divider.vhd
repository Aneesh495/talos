-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: Non-Restoring Iterative Integer Hardware Divider
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_divider is
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        flush      : in  std_logic;

        -- Ingress from Multiplier / Divider Reservation Station
        req_val    : in  std_logic;
        md_op      : in  muldiv_op_t;
        src1       : in  std_logic_vector(XLEN-1 downto 0);
        src2       : in  std_logic_vector(XLEN-1 downto 0);
        rob_idx_in : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_in : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);
        busy       : out std_logic;

        -- Egress to Common Data Bus Arbiter
        resp_val   : out std_logic;
        resp_res   : out std_logic_vector(XLEN-1 downto 0);
        rob_idx_out: out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_out: out std_logic_vector(PHYS_REG_BITS-1 downto 0)
    );
end entity talos_divider;

architecture rtl of talos_divider is

    type state_t is (ST_IDLE, ST_DIVIDE, ST_DONE);
    signal state_reg : state_t := ST_IDLE;

    signal count_reg     : integer range 0 to 32 := 0;
    signal op_reg        : muldiv_op_t;
    signal rob_idx_reg   : std_logic_vector(ROB_INDEX_BITS-1 downto 0) := (others => '0');
    signal rd_phys_reg   : std_logic_vector(PHYS_REG_BITS-1 downto 0) := (others => '0');

    signal quot_sign_reg : std_logic := '0';
    signal rem_sign_reg  : std_logic := '0';

    signal dividend_reg  : unsigned(31 downto 0) := (others => '0');
    signal divisor_reg   : unsigned(31 downto 0) := (others => '0');
    signal quotient_reg  : unsigned(31 downto 0) := (others => '0');
    signal remainder_reg : unsigned(31 downto 0) := (others => '0');

    signal result_reg    : std_logic_vector(XLEN-1 downto 0) := (others => '0');

begin

    busy <= '1' when state_reg /= ST_IDLE else '0';

    process(clk, rst_n)
        variable is_signed : boolean;
        variable s1_s      : signed(31 downto 0);
        variable s2_s      : signed(31 downto 0);
        variable div_a     : unsigned(31 downto 0);
        variable div_b     : unsigned(31 downto 0);
        variable rem_temp  : unsigned(32 downto 0);
        variable q_bit     : std_logic;
    begin
        if rst_n = '0' then
            state_reg     <= ST_IDLE;
            count_reg     <= 0;
            resp_val      <= '0';
            resp_res      <= (others => '0');
            rob_idx_out   <= (others => '0');
            rd_phys_out   <= (others => '0');
            dividend_reg  <= (others => '0');
            divisor_reg   <= (others => '0');
            quotient_reg  <= (others => '0');
            remainder_reg <= (others => '0');
            result_reg    <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                state_reg <= ST_IDLE;
                resp_val  <= '0';
            else
                case state_reg is
                    when ST_IDLE =>
                        resp_val <= '0';
                        if req_val = '1' and (md_op = MD_DIV or md_op = MD_DIVU or md_op = MD_REM or md_op = MD_REMU) then
                            op_reg      <= md_op;
                            rob_idx_reg <= rob_idx_in;
                            rd_phys_reg <= rd_phys_in;
                            s1_s        := signed(src1);
                            s2_s        := signed(src2);

                            is_signed := (md_op = MD_DIV or md_op = MD_REM);

                            -- Extract magnitudes and sign bits
                            if is_signed then
                                if s1_s < 0 then
                                    div_a := unsigned(-s1_s);
                                else
                                    div_a := unsigned(s1_s);
                                end if;

                                if s2_s < 0 then
                                    div_b := unsigned(-s2_s);
                                else
                                    div_b := unsigned(s2_s);
                                end if;

                                quot_sign_reg <= src1(31) xor src2(31);
                                rem_sign_reg  <= src1(31);
                            else
                                div_a := unsigned(src1);
                                div_b := unsigned(src2);
                                quot_sign_reg <= '0';
                                rem_sign_reg  <= '0';
                            end if;

                            -- Special case: Division by Zero
                            if div_b = 0 then
                                if md_op = MD_DIV or md_op = MD_DIVU then
                                    result_reg <= (others => '1'); -- -1
                                else
                                    result_reg <= src1; -- remainder is dividend
                                end if;
                                state_reg <= ST_DONE;

                            -- Special case: Signed Overflow (-2^31 / -1)
                            elsif is_signed and src1 = x"80000000" and src2 = x"FFFFFFFF" then
                                if md_op = MD_DIV then
                                    result_reg <= x"80000000";
                                else
                                    result_reg <= x"00000000";
                                end if;
                                state_reg <= ST_DONE;

                            else
                                dividend_reg  <= div_a;
                                divisor_reg   <= div_b;
                                quotient_reg  <= (others => '0');
                                remainder_reg <= (others => '0');
                                count_reg     <= 32;
                                state_reg     <= ST_DIVIDE;
                            end if;
                        end if;

                    when ST_DIVIDE =>
                        -- Non-restoring single-bit shift and subtract step
                        rem_temp := (remainder_reg(30 downto 0) & dividend_reg(31)) - ('0' & divisor_reg);
                        if rem_temp(32) = '0' then
                            -- Subtraction succeeded
                            remainder_reg <= rem_temp(31 downto 0);
                            q_bit := '1';
                        else
                            -- Subtraction failed
                            remainder_reg <= remainder_reg(30 downto 0) & dividend_reg(31);
                            q_bit := '0';
                        end if;

                        dividend_reg <= dividend_reg(30 downto 0) & '0';
                        quotient_reg <= quotient_reg(30 downto 0) & q_bit;

                        if count_reg = 1 then
                            state_reg <= ST_DONE;
                        else
                            count_reg <= count_reg - 1;
                        end if;

                    when ST_DONE =>
                        -- Apply sign negation if necessary
                        if op_reg = MD_DIV or op_reg = MD_DIVU then
                            if quot_sign_reg = '1' and result_reg = (result_reg'range => '0') then
                                result_reg <= std_logic_vector(-signed(quotient_reg));
                            elsif result_reg = (result_reg'range => '0') then
                                result_reg <= std_logic_vector(quotient_reg);
                            end if;
                        else
                            if rem_sign_reg = '1' and result_reg = (result_reg'range => '0') then
                                result_reg <= std_logic_vector(-signed(remainder_reg));
                            elsif result_reg = (result_reg'range => '0') then
                                result_reg <= std_logic_vector(remainder_reg);
                            end if;
                        end if;

                        resp_val    <= '1';
                        resp_res    <= result_reg;
                        rob_idx_out <= rob_idx_reg;
                        rd_phys_out <= rd_phys_reg;
                        state_reg   <= ST_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
