-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Rename: Speculative Register Alias Table (RAT) with Intra-Cycle Forwarding
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_rat is
    generic (
        ARCH_REGS   : integer := 32;
        PHYS_REGS   : integer := 64;
        TAG_BITS    : integer := 6
    );
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;

        -- Instruction 0 Rename Ports
        ren_req0          : in  std_logic;
        rs1_arch0         : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rs2_arch0         : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rd_arch0          : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        alloc_tag0        : in  std_logic_vector(TAG_BITS-1 downto 0);
        has_dest0         : in  std_logic;

        rs1_phys0         : out std_logic_vector(TAG_BITS-1 downto 0);
        rs1_ready0        : out std_logic;
        rs2_phys0         : out std_logic_vector(TAG_BITS-1 downto 0);
        rs2_ready0        : out std_logic;
        old_rd_phys0      : out std_logic_vector(TAG_BITS-1 downto 0);

        -- Instruction 1 Rename Ports
        ren_req1          : in  std_logic;
        rs1_arch1         : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rs2_arch1         : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rd_arch1          : in  std_logic_vector(ARCH_REG_BITS-1 downto 0);
        alloc_tag1        : in  std_logic_vector(TAG_BITS-1 downto 0);
        has_dest1         : in  std_logic;

        rs1_phys1         : out std_logic_vector(TAG_BITS-1 downto 0);
        rs1_ready1        : out std_logic;
        rs2_phys1         : out std_logic_vector(TAG_BITS-1 downto 0);
        rs2_ready1        : out std_logic;
        old_rd_phys1      : out std_logic_vector(TAG_BITS-1 downto 0);

        -- Common Data Bus Snooping (Ready Bit Updates)
        cdb_bus           : in  cdb_bus_t;

        -- Checkpoint / Recovery Interface
        restore_valid     : in  std_logic;
        restore_rat_table : in  std_logic_vector(ARCH_REGS*TAG_BITS-1 downto 0);
        restore_ready_mask: in  std_logic_vector(PHYS_REGS-1 downto 0);
        current_rat_table : out std_logic_vector(ARCH_REGS*TAG_BITS-1 downto 0);
        current_ready_mask: out std_logic_vector(PHYS_REGS-1 downto 0)
    );
end entity talos_rat;

architecture rtl of talos_rat is

    type rat_array_t is array (0 to ARCH_REGS-1) of std_logic_vector(TAG_BITS-1 downto 0);

    -- Initial architectural mapping: x(i) -> p(i)
    function init_rat return rat_array_t is
        variable r : rat_array_t;
    begin
        for i in 0 to ARCH_REGS-1 loop
            r(i) := std_logic_vector(to_unsigned(i, TAG_BITS));
        end loop;
        return r;
    end function init_rat;

    signal rat_table  : rat_array_t := init_rat;
    signal ready_mask : std_logic_vector(PHYS_REGS-1 downto 0) := (
        0 => '1', -- p0 (x0) is hardwired zero and always ready
        31 downto 1 => '1',
        others => '0'
    );

begin

    -- Flatten table for checkpointing
    process(rat_table, ready_mask)
        variable flat : std_logic_vector(ARCH_REGS*TAG_BITS-1 downto 0);
    begin
        for i in 0 to ARCH_REGS-1 loop
            flat((i+1)*TAG_BITS-1 downto i*TAG_BITS) := rat_table(i);
        end loop;
        current_rat_table  <= flat;
        current_ready_mask <= ready_mask;
    end process;

    -- Instruction 0 Renaming (Pure RAT lookup)
    process(rs1_arch0, rs2_arch0, rd_arch0, rat_table, ready_mask)
        variable idx_rs1 : integer range 0 to ARCH_REGS-1;
        variable idx_rs2 : integer range 0 to ARCH_REGS-1;
        variable idx_rd  : integer range 0 to ARCH_REGS-1;
        variable p_rs1   : std_logic_vector(TAG_BITS-1 downto 0);
        variable p_rs2   : std_logic_vector(TAG_BITS-1 downto 0);
    begin
        idx_rs1 := to_integer(unsigned(rs1_arch0));
        idx_rs2 := to_integer(unsigned(rs2_arch0));
        idx_rd  := to_integer(unsigned(rd_arch0));

        p_rs1 := rat_table(idx_rs1);
        p_rs2 := rat_table(idx_rs2);

        rs1_phys0    <= p_rs1;
        rs1_ready0   <= ready_mask(to_integer(unsigned(p_rs1)));
        rs2_phys0    <= p_rs2;
        rs2_ready0   <= ready_mask(to_integer(unsigned(p_rs2)));
        old_rd_phys0 <= rat_table(idx_rd);
    end process;

    -- Instruction 1 Renaming (With Intra-Cycle Forwarding from Instruction 0)
    process(rs1_arch1, rs2_arch1, rd_arch1, rat_table, ready_mask,
            ren_req0, has_dest0, rd_arch0, alloc_tag0)
        variable idx_rs1 : integer range 0 to ARCH_REGS-1;
        variable idx_rs2 : integer range 0 to ARCH_REGS-1;
        variable idx_rd  : integer range 0 to ARCH_REGS-1;
        variable p_rs1   : std_logic_vector(TAG_BITS-1 downto 0);
        variable p_rs2   : std_logic_vector(TAG_BITS-1 downto 0);
        variable r1_rdy  : std_logic;
        variable r2_rdy  : std_logic;
    begin
        idx_rs1 := to_integer(unsigned(rs1_arch1));
        idx_rs2 := to_integer(unsigned(rs2_arch1));
        idx_rd  := to_integer(unsigned(rd_arch1));

        -- Check if Way 1 reads Way 0's destination register
        if ren_req0 = '1' and has_dest0 = '1' and to_integer(unsigned(rd_arch0)) /= 0 and rs1_arch1 = rd_arch0 then
            p_rs1  := alloc_tag0;
            r1_rdy := '0'; -- Freshly allocated in same cycle, not yet ready
        else
            p_rs1  := rat_table(idx_rs1);
            r1_rdy := ready_mask(to_integer(unsigned(p_rs1)));
        end if;

        if ren_req0 = '1' and has_dest0 = '1' and to_integer(unsigned(rd_arch0)) /= 0 and rs2_arch1 = rd_arch0 then
            p_rs2  := alloc_tag0;
            r2_rdy := '0';
        else
            p_rs2  := rat_table(idx_rs2);
            r2_rdy := ready_mask(to_integer(unsigned(p_rs2)));
        end if;

        rs1_phys1  <= p_rs1;
        rs1_ready1 <= r1_rdy;
        rs2_phys1  <= p_rs2;
        rs2_ready1 <= r2_rdy;

        -- Old physical register for Way 1: If Way 0 wrote same architectural register, Way 1's old tag is Way 0's new tag
        if ren_req0 = '1' and has_dest0 = '1' and to_integer(unsigned(rd_arch0)) /= 0 and rd_arch1 = rd_arch0 then
            old_rd_phys1 <= alloc_tag0;
        else
            old_rd_phys1 <= rat_table(idx_rd);
        end if;
    end process;

    -- RAT Table and Ready Mask State Update
    process(clk, rst_n)
        variable rat_next   : rat_array_t;
        variable ready_next : std_logic_vector(PHYS_REGS-1 downto 0);
        variable cdb_tag    : integer range 0 to PHYS_REGS-1;
    begin
        if rst_n = '0' then
            rat_table  <= init_rat;
            ready_mask <= (0 => '1', 31 downto 1 => '1', others => '0');
        elsif rising_edge(clk) then
            if restore_valid = '1' then
                -- Single-cycle branch misprediction restoration
                for i in 0 to ARCH_REGS-1 loop
                    rat_table(i) <= restore_rat_table((i+1)*TAG_BITS-1 downto i*TAG_BITS);
                end loop;
                ready_mask <= restore_ready_mask;
            else
                rat_next   := rat_table;
                ready_next := ready_mask;

                -- 1. SNOOP CDB BROADCASTS: Wake up completed physical registers
                for c in 0 to CDB_CHANNELS-1 loop
                    if cdb_bus(c).valid = '1' then
                        cdb_tag := to_integer(unsigned(cdb_bus(c).phys_tag));
                        if cdb_tag /= 0 then
                            ready_next(cdb_tag) := '1';
                        end if;
                    end if;
                end loop;

                -- 2. APPLY WAY 0 ALLOCATION
                if ren_req0 = '1' and has_dest0 = '1' and to_integer(unsigned(rd_arch0)) /= 0 then
                    rat_next(to_integer(unsigned(rd_arch0))) := alloc_tag0;
                    ready_next(to_integer(unsigned(alloc_tag0))) := '0';
                end if;

                -- 3. APPLY WAY 1 ALLOCATION
                if ren_req1 = '1' and has_dest1 = '1' and to_integer(unsigned(rd_arch1)) /= 0 then
                    rat_next(to_integer(unsigned(rd_arch1))) := alloc_tag1;
                    ready_next(to_integer(unsigned(alloc_tag1))) := '0';
                end if;

                -- Hardwire p0 ready
                ready_next(0) := '1';

                rat_table  <= rat_next;
                ready_mask <= ready_next;
            end if;
        end if;
    end process;

end architecture rtl;
