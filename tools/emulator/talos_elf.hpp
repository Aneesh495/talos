// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: ELF32, Hex, and Raw Binary Image Loader Header
// Standard: C++20
// ==============================================================================

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace talos {

class ElfLoader {
public:
    static bool load_elf(
        const std::string& path,
        std::vector<uint8_t>& memory,
        uint32_t mem_base,
        uint32_t& entrypoint,
        uint32_t& tohost_addr
    );

    static bool load_hex(
        const std::string& path,
        std::vector<uint8_t>& memory,
        uint32_t mem_base
    );

    static bool load_bin(
        const std::string& path,
        std::vector<uint8_t>& memory,
        uint32_t mem_base,
        uint32_t load_offset = 0
    );
};

} // namespace talos
