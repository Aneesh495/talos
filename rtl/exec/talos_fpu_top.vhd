-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: Integrated IEEE-754 Single-Precision FPU Execution Pipeline
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;
use work.talos_fpu_pkg.all;

entity talos_fpu_top is
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        flush       : in  std_logic;

        -- Ingress from FPU Reservation Station
        req_val     : in  std_logic;
        fpu_op      : in  fpu_op_t;
        src1        : in  std_logic_vector(XLEN-1 downto 0);
        src2        : in  std_logic_vector(XLEN-1 downto 0);
        src3        : in  std_logic_vector(XLEN-1 downto 0);
        rm          : in  std_logic_vector(2 downto 0);
        rob_idx_in  : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_in  : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);

        -- Egress to Common Data Bus Arbiter
        resp_val    : out std_logic;
        resp_data   : out std_logic_vector(XLEN-1 downto 0);
        resp_flags  : out std_logic_vector(4 downto 0);
        rob_idx_out : out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_out : out std_logic_vector(PHYS_REG_BITS-1 downto 0)
    );
end entity talos_fpu_top;

architecture rtl of talos_fpu_top is

    signal add_req     : std_logic;
    signal is_sub      : std_logic;
    signal add_val     : std_logic;
    signal add_data    : std_logic_vector(31 downto 0);
    signal add_flags   : std_logic_vector(4 downto 0);

    signal mul_req     : std_logic;
    signal mul_val     : std_logic;
    signal mul_data    : std_logic_vector(31 downto 0);
    signal mul_flags   : std_logic_vector(4 downto 0);

    signal pipe_rob_idx: std_logic_vector(ROB_INDEX_BITS-1 downto 0) := (others => '0');
    signal pipe_rd_phys: std_logic_vector(PHYS_REG_BITS-1 downto 0) := (others => '0');
    signal pipe_op     : fpu_op_t := FPU_NONE;

    signal misc_val    : std_logic := '0';
    signal misc_data   : std_logic_vector(31 downto 0) := (others => '0');
    signal misc_flags  : std_logic_vector(4 downto 0) := (others => '0');

begin

    add_req <= req_val when (fpu_op = FPU_ADD or fpu_op = FPU_SUB) else '0';
    is_sub  <= '1' when fpu_op = FPU_SUB else '0';
    mul_req <= req_val when fpu_op = FPU_MUL else '0';

    -- 1. FPU Adder
    u_adder : entity work.talos_fpu_adder
        port map (
            clk       => clk,
            rst_n     => rst_n,
            req_val   => add_req,
            is_sub    => is_sub,
            src1      => src1,
            src2      => src2,
            rm        => rm,
            res_val   => add_val,
            res_data  => add_data,
            res_flags => add_flags
        );

    -- 2. FPU Multiplier
    u_mult : entity work.talos_fpu_mult
        port map (
            clk       => clk,
            rst_n     => rst_n,
            req_val   => mul_req,
            src1      => src1,
            src2      => src2,
            rm        => rm,
            res_val   => mul_val,
            res_data  => mul_data,
            res_flags => mul_flags
        );

    -- 3. Float Conversions and Comparisons (Single cycle execution)
    process(clk, rst_n)
        variable s1_f, s2_f : std_logic_vector(31 downto 0);
        variable feq, flt   : boolean;
        variable flags      : std_logic_vector(4 downto 0);
        variable res        : std_logic_vector(31 downto 0);
    begin
        if rst_n = '0' then
            misc_val   <= '0';
            misc_data  <= (others => '0');
            misc_flags <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                misc_val <= '0';
            else
                misc_val <= req_val and bool_to_sl(fpu_op = FPU_FEQ or fpu_op = FPU_FLT or fpu_op = FPU_FLE or fpu_op = FPU_CVT_W_S or fpu_op = FPU_CVT_S_W);
                flags    := (others => '0');
                res      := (others => '0');
                s1_f     := src1;
                s2_f     := src2;

                if fp_is_nan(s1_f) or fp_is_nan(s2_f) then
                    flags(FP_FLAG_NV_BIT) := '1';
                else
                    feq := (s1_f = s2_f) or (fp_is_zero(s1_f) and fp_is_zero(s2_f));
                    if s1_f(31) /= s2_f(31) then
                        flt := (s1_f(31) = '1');
                    elsif s1_f(31) = '0' then
                        flt := (unsigned(s1_f) < unsigned(s2_f));
                    else
                        flt := (unsigned(s1_f) > unsigned(s2_f));
                    end if;

                    case fpu_op is
                        when FPU_FEQ =>
                            if feq then res := (0 => '1', others => '0'); end if;
                        when FPU_FLT =>
                            if flt and not feq then res := (0 => '1', others => '0'); end if;
                        when FPU_FLE =>
                            if flt or feq then res := (0 => '1', others => '0'); end if;
                        when FPU_CVT_W_S =>
                            -- Float to signed 32-bit int
                            res := std_logic_vector(to_signed(to_integer(unsigned(s1_f(22 downto 0))), 32));
                        when FPU_CVT_S_W =>
                            -- Int to float
                            res := x"40000000"; -- Basic normalized representation stub
                        when others =>
                            null;
                    end case;
                end if;

                misc_data  <= res;
                misc_flags <= flags;
            end if;
        end if;
    end process;

    -- Pipeline metadata registers
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            pipe_rob_idx <= (others => '0');
            pipe_rd_phys <= (others => '0');
            pipe_op      <= FPU_NONE;
        elsif rising_edge(clk) then
            if flush = '1' then
                pipe_rob_idx <= (others => '0');
                pipe_rd_phys <= (others => '0');
                pipe_op      <= FPU_NONE;
            elsif req_val = '1' then
                pipe_rob_idx <= rob_idx_in;
                pipe_rd_phys <= rd_phys_in;
                pipe_op      <= fpu_op;
            end if;
        end if;
    end process;

    -- Multiplex output to CDB
    process(add_val, add_data, add_flags, mul_val, mul_data, mul_flags, misc_val, misc_data, misc_flags, pipe_rob_idx, pipe_rd_phys)
    begin
        rob_idx_out <= pipe_rob_idx;
        rd_phys_out <= pipe_rd_phys;

        if add_val = '1' then
            resp_val   <= '1';
            resp_data  <= add_data;
            resp_flags <= add_flags;
        elsif mul_val = '1' then
            resp_val   <= '1';
            resp_data  <= mul_data;
            resp_flags <= mul_flags;
        elsif misc_val = '1' then
            resp_val   <= '1';
            resp_data  <= misc_data;
            resp_flags <= misc_flags;
        else
            resp_val   <= '0';
            resp_data  <= (others => '0');
            resp_flags <= (others => '0');
        end if;
    end process;

end architecture rtl;
