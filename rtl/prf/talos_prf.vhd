-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Physical Register File: 64-Entry Multi-Port Register File with CDB Write Bypass
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.talos_pkg.all;

entity talos_prf is
    generic (
        PREGS    : integer := PHYS_REG_COUNT; -- 64
        TAG_BITS : integer := PHYS_REG_BITS   -- 6
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;

        -- 6 Read Ports (Combinational with Intra-Cycle CDB Bypass)
        raddr0   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata0   : out std_logic_vector(XLEN-1 downto 0);

        raddr1   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata1   : out std_logic_vector(XLEN-1 downto 0);

        raddr2   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata2   : out std_logic_vector(XLEN-1 downto 0);

        raddr3   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata3   : out std_logic_vector(XLEN-1 downto 0);

        raddr4   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata4   : out std_logic_vector(XLEN-1 downto 0);

        raddr5   : in  std_logic_vector(TAG_BITS-1 downto 0);
        rdata5   : out std_logic_vector(XLEN-1 downto 0);

        -- Common Data Bus Write Ports (5 Concurrent Channels)
        cdb_bus  : in  cdb_bus_t
    );
end entity talos_prf;

architecture rtl of talos_prf is

    type reg_array_t is array (0 to PREGS-1) of std_logic_vector(XLEN-1 downto 0);
    signal reg_file : reg_array_t := (others => (others => '0'));

    -- Read port with priority CDB bypass
    function read_with_bypass(
        addr     : std_logic_vector(TAG_BITS-1 downto 0);
        storage  : reg_array_t;
        cdb      : cdb_bus_t
    ) return std_logic_vector is
        variable a_int : integer range 0 to PREGS-1;
    begin
        a_int := to_integer(unsigned(addr));
        -- p0 is hardwired zero
        if a_int = 0 then
            return (XLEN-1 downto 0 => '0');
        end if;

        -- Intra-cycle bypass: Check active CDB broadcasts
        for c in 0 to CDB_CHANNELS-1 loop
            if cdb(c).valid = '1' and cdb(c).phys_tag = addr then
                return cdb(c).value;
            end if;
        end loop;

        -- Return storage value
        return storage(a_int);
    end function read_with_bypass;

begin

    -- Combinational Read Ports
    rdata0 <= read_with_bypass(raddr0, reg_file, cdb_bus);
    rdata1 <= read_with_bypass(raddr1, reg_file, cdb_bus);
    rdata2 <= read_with_bypass(raddr2, reg_file, cdb_bus);
    rdata3 <= read_with_bypass(raddr3, reg_file, cdb_bus);
    rdata4 <= read_with_bypass(raddr4, reg_file, cdb_bus);
    rdata5 <= read_with_bypass(raddr5, reg_file, cdb_bus);

    -- Synchronous Write Ports from CDB
    process(clk, rst_n)
        variable tag_int : integer range 0 to PREGS-1;
    begin
        if rst_n = '0' then
            reg_file <= (others => (others => '0'));
        elsif rising_edge(clk) then
            for c in 0 to CDB_CHANNELS-1 loop
                if cdb_bus(c).valid = '1' then
                    tag_int := to_integer(unsigned(cdb_bus(c).phys_tag));
                    if tag_int /= 0 then
                        reg_file(tag_int) <= cdb_bus(c).value;
                    end if;
                end if;
            end loop;
        end if;
    end process;

end architecture rtl;
