-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Execution: 3-Stage Pipelined High-Frequency Integer Multiplier
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_multiplier is
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        flush      : in  std_logic;

        -- Ingress from Multiplier Reservation Station
        req_val    : in  std_logic;
        md_op      : in  muldiv_op_t;
        src1       : in  std_logic_vector(XLEN-1 downto 0);
        src2       : in  std_logic_vector(XLEN-1 downto 0);
        rob_idx_in : in  std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_in : in  std_logic_vector(PHYS_REG_BITS-1 downto 0);

        -- Egress to Common Data Bus Arbiter
        resp_val   : out std_logic;
        resp_res   : out std_logic_vector(XLEN-1 downto 0);
        rob_idx_out: out std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        rd_phys_out: out std_logic_vector(PHYS_REG_BITS-1 downto 0)
    );
end entity talos_multiplier;

architecture rtl of talos_multiplier is

    -- Stage 1 Pipeline Registers
    signal s1_valid    : std_logic := '0';
    signal s1_op       : muldiv_op_t;
    signal s1_rob_idx  : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal s1_rd_phys  : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal s1_op_a_ext : signed(32 downto 0);
    signal s1_op_b_ext : signed(32 downto 0);

    -- Stage 2 Pipeline Registers
    signal s2_valid    : std_logic := '0';
    signal s2_op       : muldiv_op_t;
    signal s2_rob_idx  : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
    signal s2_rd_phys  : std_logic_vector(PHYS_REG_BITS-1 downto 0);
    signal s2_product  : signed(65 downto 0);

    -- Stage 3 Output Registers
    signal s3_valid    : std_logic := '0';
    signal s3_res      : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    signal s3_rob_idx  : std_logic_vector(ROB_INDEX_BITS-1 downto 0) := (others => '0');
    signal s3_rd_phys  : std_logic_vector(PHYS_REG_BITS-1 downto 0) := (others => '0');

begin

    -- Stage 1: Operand Sign Extension
    process(clk, rst_n)
        variable a_signed, b_signed : signed(32 downto 0);
    begin
        if rst_n = '0' then
            s1_valid    <= '0';
            s1_op       <= MD_NONE;
            s1_rob_idx  <= (others => '0');
            s1_rd_phys  <= (others => '0');
            s1_op_a_ext <= (others => '0');
            s1_op_b_ext <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                s1_valid <= '0';
            else
                s1_valid   <= req_val and bool_to_sl(md_op = MD_MUL or md_op = MD_MULH or md_op = MD_MULHSU or md_op = MD_MULHU);
                s1_op      <= md_op;
                s1_rob_idx <= rob_idx_in;
                s1_rd_phys <= rd_phys_in;

                -- Source 1 Extension
                if md_op = MD_MULHU then
                    a_signed := signed("0" & src1);
                else
                    a_signed := signed(src1(31) & src1);
                end if;

                -- Source 2 Extension
                if md_op = MD_MULH then
                    b_signed := signed(src2(31) & src2);
                else
                    b_signed := signed("0" & src2);
                end if;

                s1_op_a_ext <= a_signed;
                s1_op_b_ext <= b_signed;
            end if;
        end if;
    end process;

    -- Stage 2: Carry-Save Multiplication
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            s2_valid   <= '0';
            s2_op      <= MD_NONE;
            s2_rob_idx <= (others => '0');
            s2_rd_phys <= (others => '0');
            s2_product <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                s2_valid <= '0';
            else
                s2_valid   <= s1_valid;
                s2_op      <= s1_op;
                s2_rob_idx <= s1_rob_idx;
                s2_rd_phys <= s1_rd_phys;
                s2_product <= s1_op_a_ext * s1_op_b_ext;
            end if;
        end if;
    end process;

    -- Stage 3: Product Slicing (Lower vs Upper Word)
    process(clk, rst_n)
        variable p64 : std_logic_vector(63 downto 0);
    begin
        if rst_n = '0' then
            s3_valid   <= '0';
            s3_res     <= (others => '0');
            s3_rob_idx <= (others => '0');
            s3_rd_phys <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                s3_valid <= '0';
            else
                s3_valid   <= s2_valid;
                s3_rob_idx <= s2_rob_idx;
                s3_rd_phys <= s2_rd_phys;

                p64 := std_logic_vector(s2_product(63 downto 0));
                case s2_op is
                    when MD_MUL =>
                        s3_res <= p64(31 downto 0);
                    when MD_MULH | MD_MULHSU | MD_MULHU =>
                        s3_res <= p64(63 downto 32);
                    when others =>
                        s3_res <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    resp_val    <= s3_valid;
    resp_res    <= s3_res;
    rob_idx_out <= s3_rob_idx;
    rd_phys_out <= s3_rd_phys;

end architecture rtl;
