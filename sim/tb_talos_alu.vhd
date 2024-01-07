-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Testbench: Integer Arithmetic Logic Unit (ALU)
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity tb_talos_alu is
end entity tb_talos_alu;

architecture sim of tb_talos_alu is

    signal alu_op : alu_op_t := ALU_ADD;
    signal src1   : std_logic_vector(31 downto 0) := (others => '0');
    signal src2   : std_logic_vector(31 downto 0) := (others => '0');
    signal pc     : std_logic_vector(31 downto 0) := (others => '0');
    signal imm    : std_logic_vector(31 downto 0) := (others => '0');
    signal res    : std_logic_vector(31 downto 0);
    signal zero   : std_logic;

begin

    dut : entity work.talos_alu
        port map (
            alu_op => alu_op,
            src1   => src1,
            src2   => src2,
            pc     => pc,
            imm    => imm,
            res    => res,
            zero   => zero
        );

    process
    begin
        report "[TEST] Starting tb_talos_alu verification...";

        -- 1. ADD: 15 + 27 = 42
        alu_op <= ALU_ADD;
        src1   <= std_logic_vector(to_signed(15, 32));
        src2   <= std_logic_vector(to_signed(27, 32));
        wait for 10 ns;
        assert res = std_logic_vector(to_signed(42, 32)) report "ADD failed" severity failure;
        assert zero = '0' report "Zero flag error on ADD" severity failure;

        -- 2. SUB: 100 - 100 = 0 (zero flag set)
        alu_op <= ALU_SUB;
        src1   <= std_logic_vector(to_signed(100, 32));
        src2   <= std_logic_vector(to_signed(100, 32));
        wait for 10 ns;
        assert res = x"00000000" report "SUB failed" severity failure;
        assert zero = '1' report "Zero flag should be 1" severity failure;

        -- 3. Logical Shift Left (SLL): 1 << 4 = 16
        alu_op <= ALU_SLL;
        src1   <= x"00000001";
        src2   <= x"00000004";
        wait for 10 ns;
        assert res = x"00000010" report "SLL failed" severity failure;

        -- 4. Arithmetic Shift Right (SRA): -16 >> 2 = -4
        alu_op <= ALU_SRA;
        src1   <= std_logic_vector(to_signed(-16, 32));
        src2   <= x"00000002";
        wait for 10 ns;
        assert res = std_logic_vector(to_signed(-4, 32)) report "SRA failed" severity failure;

        -- 5. SLT: Signed less than (-10 < 5 is true -> 1)
        alu_op <= ALU_SLT;
        src1   <= std_logic_vector(to_signed(-10, 32));
        src2   <= std_logic_vector(to_signed(5, 32));
        wait for 10 ns;
        assert res = x"00000001" report "SLT signed failed" severity failure;

        -- 6. SLTU: Unsigned less than (0xFFFFFFFF < 5 is false -> 0)
        alu_op <= ALU_SLTU;
        src1   <= x"FFFFFFFF";
        src2   <= x"00000005";
        wait for 10 ns;
        assert res = x"00000000" report "SLTU unsigned failed" severity failure;

        -- 7. Bitwise XOR, OR, AND
        alu_op <= ALU_XOR;
        src1   <= x"00FF00FF";
        src2   <= x"0F0F0F0F";
        wait for 10 ns;
        assert res = x"0FF00FF0" report "XOR failed" severity failure;

        -- 8. AUIPC: pc + imm
        alu_op <= ALU_AUIPC;
        pc     <= x"80001000";
        imm    <= x"00002000";
        wait for 10 ns;
        assert res = x"80003000" report "AUIPC failed" severity failure;

        report "[PASS] tb_talos_alu verification successful.";
        wait;
    end process;

end architecture sim;
