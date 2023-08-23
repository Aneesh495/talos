-- ==============================================================================
-- Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
-- Core Package: Global Types, Microarchitectural Constants, and Record Definitions
-- Standard: VHDL-2008
-- ==============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package talos_pkg is

    -- -------------------------------------------------------------------------
    -- Architectural and Microarchitectural Parameters
    -- -------------------------------------------------------------------------
    constant XLEN                    : integer := 32;
    constant ADDR_WIDTH              : integer := 32;
    constant INSTR_WIDTH             : integer := 32;
    constant DATA_WIDTH              : integer := 32;

    constant ARCH_REG_COUNT          : integer := 32;
    constant ARCH_REG_BITS           : integer := 5;

    constant PHYS_REG_COUNT          : integer := 64;
    constant PHYS_REG_BITS           : integer := 6;

    constant ROB_DEPTH               : integer := 32;
    constant ROB_INDEX_BITS          : integer := 5;

    constant RS_ALU_DEPTH            : integer := 8;
    constant RS_MULDIV_DEPTH         : integer := 4;
    constant RS_MEM_DEPTH            : integer := 8;
    constant RS_FPU_DEPTH            : integer := 4;

    constant LQ_DEPTH                : integer := 16;
    constant LQ_INDEX_BITS           : integer := 4;

    constant SQ_DEPTH                : integer := 16;
    constant SQ_INDEX_BITS           : integer := 4;

    constant CKPT_COUNT              : integer := 8;
    constant CKPT_ID_BITS            : integer := 3;

    constant MSHR_DEPTH              : integer := 4;
    constant MSHR_INDEX_BITS         : integer := 2;

    constant LINE_SIZE_BYTES         : integer := 32;
    constant LINE_SIZE_BITS          : integer := 256;
    constant LINE_OFFSET_BITS        : integer := 5;

    constant FETCH_WIDTH             : integer := 2;
    constant ISSUE_WIDTH             : integer := 2;
    constant COMMIT_WIDTH            : integer := 2;
    constant CDB_CHANNELS            : integer := 5;

    -- -------------------------------------------------------------------------
    -- Functional Unit Classification
    -- -------------------------------------------------------------------------
    type fu_type_t is (
        FU_NONE,
        FU_ALU0,
        FU_ALU1,
        FU_BRANCH,
        FU_MULDIV,
        FU_MEM,
        FU_FPU,
        FU_CSR
    );

    -- -------------------------------------------------------------------------
    -- Arithmetic Logic Unit Operations
    -- -------------------------------------------------------------------------
    type alu_op_t is (
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_SRL,
        ALU_SRA,
        ALU_OR,
        ALU_AND,
        ALU_LUI,
        ALU_AUIPC
    );

    -- -------------------------------------------------------------------------
    -- Branch Unit Operations
    -- -------------------------------------------------------------------------
    type branch_op_t is (
        BR_NONE,
        BR_BEQ,
        BR_BNE,
        BR_BLT,
        BR_BGE,
        BR_BLTU,
        BR_BGEU,
        BR_JAL,
        BR_JALR
    );

    -- -------------------------------------------------------------------------
    -- Multiply / Divide Unit Operations
    -- -------------------------------------------------------------------------
    type muldiv_op_t is (
        MD_NONE,
        MD_MUL,
        MD_MULH,
        MD_MULHSU,
        MD_MULHU,
        MD_DIV,
        MD_DIVU,
        MD_REM,
        MD_REMU
    );

    -- -------------------------------------------------------------------------
    -- Memory Access Operations
    -- -------------------------------------------------------------------------
    type mem_op_t is (
        MEM_NONE,
        MEM_LB,
        MEM_LH,
        MEM_LW,
        MEM_LBU,
        MEM_LHU,
        MEM_SB,
        MEM_SH,
        MEM_SW
    );

    -- -------------------------------------------------------------------------
    -- Floating-Point Unit Operations
    -- -------------------------------------------------------------------------
    type fpu_op_t is (
        FPU_NONE,
        FPU_ADD,
        FPU_SUB,
        FPU_MUL,
        FPU_DIV,
        FPU_SQRT,
        FPU_CVT_W_S,
        FPU_CVT_S_W,
        FPU_FEQ,
        FPU_FLT,
        FPU_FLE,
        FPU_FMIN,
        FPU_FMAX
    );

    -- -------------------------------------------------------------------------
    -- Fetch Packet Structure
    -- -------------------------------------------------------------------------
    type fetch_pkt_t is record
        valid       : std_logic;
        pc          : std_logic_vector(ADDR_WIDTH-1 downto 0);
        instr       : std_logic_vector(INSTR_WIDTH-1 downto 0);
        pred_taken  : std_logic;
        pred_target : std_logic_vector(ADDR_WIDTH-1 downto 0);
        is_rvc      : std_logic;
    end record fetch_pkt_t;

    type fetch_bundle_t is array (0 to FETCH_WIDTH-1) of fetch_pkt_t;

    constant FETCH_PKT_ZERO : fetch_pkt_t := (
        valid       => '0',
        pc          => (others => '0'),
        instr       => (others => '0'),
        pred_taken  => '0',
        pred_target => (others => '0'),
        is_rvc      => '0'
    );

    -- -------------------------------------------------------------------------
    -- Decoded Instruction Packet Structure
    -- -------------------------------------------------------------------------
    type decode_pkt_t is record
        valid       : std_logic;
        pc          : std_logic_vector(ADDR_WIDTH-1 downto 0);
        instr       : std_logic_vector(INSTR_WIDTH-1 downto 0);
        fu_type     : fu_type_t;
        alu_op      : alu_op_t;
        br_op       : branch_op_t;
        md_op       : muldiv_op_t;
        mem_op      : mem_op_t;
        fpu_op      : fpu_op_t;
        rs1_arch    : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rs2_arch    : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rs3_arch    : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rd_arch     : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        imm         : std_logic_vector(XLEN-1 downto 0);
        use_imm     : std_logic;
        is_branch   : std_logic;
        is_jump     : std_logic;
        is_load     : std_logic;
        is_store    : std_logic;
        is_fpu      : std_logic;
        is_csr      : std_logic;
        has_dest    : std_logic;
        pred_taken  : std_logic;
        pred_target : std_logic_vector(ADDR_WIDTH-1 downto 0);
        illegal_op  : std_logic;
    end record decode_pkt_t;

    type decode_bundle_t is array (0 to ISSUE_WIDTH-1) of decode_pkt_t;

    constant DECODE_PKT_ZERO : decode_pkt_t := (
        valid       => '0',
        pc          => (others => '0'),
        instr       => (others => '0'),
        fu_type     => FU_NONE,
        alu_op      => ALU_ADD,
        br_op       => BR_NONE,
        md_op       => MD_NONE,
        mem_op      => MEM_NONE,
        fpu_op      => FPU_NONE,
        rs1_arch    => (others => '0'),
        rs2_arch    => (others => '0'),
        rs3_arch    => (others => '0'),
        rd_arch     => (others => '0'),
        imm         => (others => '0'),
        use_imm     => '0',
        is_branch   => '0',
        is_jump     => '0',
        is_load     => '0',
        is_store    => '0',
        is_fpu      => '0',
        is_csr      => '0',
        has_dest    => '0',
        pred_taken  => '0',
        pred_target => (others => '0'),
        illegal_op  => '0'
    );

    -- -------------------------------------------------------------------------
    -- Renamed and Dispatched Instruction Packet
    -- -------------------------------------------------------------------------
    type rename_pkt_t is record
        valid        : std_logic;
        pc           : std_logic_vector(ADDR_WIDTH-1 downto 0);
        fu_type      : fu_type_t;
        alu_op       : alu_op_t;
        br_op        : branch_op_t;
        md_op        : muldiv_op_t;
        mem_op       : mem_op_t;
        fpu_op       : fpu_op_t;
        rs1_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        rs1_ready    : std_logic;
        rs2_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        rs2_ready    : std_logic;
        rs3_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        rs3_ready    : std_logic;
        rd_phys      : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        rd_arch      : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        old_rd_phys  : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        has_dest     : std_logic;
        imm          : std_logic_vector(XLEN-1 downto 0);
        use_imm      : std_logic;
        rob_idx      : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        lsq_idx      : std_logic_vector(SQ_INDEX_BITS-1 downto 0);
        ckpt_id      : std_logic_vector(CKPT_ID_BITS-1 downto 0);
        is_branch    : std_logic;
        is_jump      : std_logic;
        is_load      : std_logic;
        is_store     : std_logic;
        is_csr       : std_logic;
        pred_taken   : std_logic;
        pred_target  : std_logic_vector(ADDR_WIDTH-1 downto 0);
        illegal_op   : std_logic;
    end record rename_pkt_t;

    type rename_bundle_t is array (0 to ISSUE_WIDTH-1) of rename_pkt_t;

    constant RENAME_PKT_ZERO : rename_pkt_t := (
        valid        => '0',
        pc           => (others => '0'),
        fu_type      => FU_NONE,
        alu_op       => ALU_ADD,
        br_op        => BR_NONE,
        md_op        => MD_NONE,
        mem_op       => MEM_NONE,
        fpu_op       => FPU_NONE,
        rs1_phys     => (others => '0'),
        rs1_ready    => '0',
        rs2_phys     => (others => '0'),
        rs2_ready    => '0',
        rs3_phys     => (others => '0'),
        rs3_ready    => '0',
        rd_phys      => (others => '0'),
        rd_arch      => (others => '0'),
        old_rd_phys  => (others => '0'),
        has_dest     => '0',
        imm          => (others => '0'),
        use_imm      => '0',
        rob_idx      => (others => '0'),
        lsq_idx      => (others => '0'),
        ckpt_id      => (others => '0'),
        is_branch    => '0',
        is_jump      => '0',
        is_load      => '0',
        is_store     => '0',
        is_csr       => '0',
        pred_taken   => '0',
        pred_target  => (others => '0'),
        illegal_op   => '0'
    );

    -- -------------------------------------------------------------------------
    -- Common Data Bus (CDB) Port Definition
    -- -------------------------------------------------------------------------
    type cdb_entry_t is record
        valid      : std_logic;
        phys_tag   : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        rob_idx    : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        value      : std_logic_vector(XLEN-1 downto 0);
        exception  : std_logic;
        exc_cause  : std_logic_vector(4 downto 0);
    end record cdb_entry_t;

    type cdb_bus_t is array (0 to CDB_CHANNELS-1) of cdb_entry_t;

    constant CDB_ENTRY_ZERO : cdb_entry_t := (
        valid      => '0',
        phys_tag   => (others => '0'),
        rob_idx    => (others => '0'),
        value      => (others => '0'),
        exception  => '0',
        exc_cause  => (others => '0')
    );

    -- -------------------------------------------------------------------------
    -- Reorder Buffer (ROB) Commit Packet
    -- -------------------------------------------------------------------------
    type rob_commit_pkt_t is record
        valid       : std_logic;
        rob_idx     : std_logic_vector(ROB_INDEX_BITS-1 downto 0);
        pc          : std_logic_vector(ADDR_WIDTH-1 downto 0);
        rd_arch     : std_logic_vector(ARCH_REG_BITS-1 downto 0);
        rd_phys     : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        old_rd_phys : std_logic_vector(PHYS_REG_BITS-1 downto 0);
        has_dest    : std_logic;
        is_store    : std_logic;
        is_branch   : std_logic;
        mispredicted: std_logic;
        target_pc   : std_logic_vector(ADDR_WIDTH-1 downto 0);
        exception   : std_logic;
        exc_cause   : std_logic_vector(4 downto 0);
    end record rob_commit_pkt_t;

    type rob_commit_bundle_t is array (0 to COMMIT_WIDTH-1) of rob_commit_pkt_t;

    constant ROB_COMMIT_PKT_ZERO : rob_commit_pkt_t := (
        valid        => '0',
        rob_idx      => (others => '0'),
        pc           => (others => '0'),
        rd_arch      => (others => '0'),
        rd_phys      => (others => '0'),
        old_rd_phys  => (others => '0'),
        has_dest     => '0',
        is_store     => '0',
        is_branch    => '0',
        mispredicted => '0',
        target_pc    => (others => '0'),
        exception    => '0',
        exc_cause    => (others => '0')
    );

    -- -------------------------------------------------------------------------
    -- Utility Functions
    -- -------------------------------------------------------------------------
    function bool_to_sl(b : boolean) return std_logic;
    function sl_to_bool(s : std_logic) return boolean;
    function clog2(val : integer) return integer;

end package talos_pkg;

package body talos_pkg is

    function bool_to_sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function bool_to_sl;

    function sl_to_bool(s : std_logic) return boolean is
    begin
        return s = '1';
    end function sl_to_bool;

    function clog2(val : integer) return integer is
        variable res : integer := 0;
        variable v   : integer := 1;
    begin
        while v < val loop
            res := res + 1;
            v   := v * 2;
        end loop;
        return res;
    end function clog2;

end package body talos_pkg;
