// ==============================================================================
// Talos: Synthesizable Dual-Issue Out-of-Order RISC-V Processor Core
// Golden Emulator: ELF32, Hex, and Raw Binary Image Loader Implementation
// Standard: C++20
// ==============================================================================

#include "talos_elf.hpp"
#include <fstream>
#include <iostream>
#include <cstring>
#include <sstream>
#include <iomanip>

namespace talos {

#pragma pack(push, 1)
struct Elf32_Ehdr {
    uint8_t  e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
};

struct Elf32_Phdr {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
};

struct Elf32_Shdr {
    uint32_t sh_name;
    uint32_t sh_type;
    uint32_t sh_flags;
    uint32_t sh_addr;
    uint32_t sh_offset;
    uint32_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint32_t sh_addralign;
    uint32_t sh_entsize;
};

struct Elf32_Sym {
    uint32_t st_name;
    uint32_t st_value;
    uint32_t st_size;
    uint8_t  st_info;
    uint8_t  st_other;
    uint16_t st_shndx;
};
#pragma pack(pop)

constexpr uint32_t PT_LOAD = 1;
constexpr uint32_t SHT_SYMTAB = 2;
[[maybe_unused]] constexpr uint32_t SHT_STRTAB = 3;
[[maybe_unused]] constexpr uint16_t EM_RISCV = 243;

bool ElfLoader::load_elf(
    const std::string& path,
    std::vector<uint8_t>& memory,
    uint32_t mem_base,
    uint32_t& entrypoint,
    uint32_t& tohost_addr
) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[ElfLoader] Error: Unable to open ELF file: " << path << "\n";
        return false;
    }

    file.seekg(0, std::ios::end);
    size_t file_size = file.tellg();
    file.seekg(0, std::ios::beg);

    if (file_size < sizeof(Elf32_Ehdr)) {
        std::cerr << "[ElfLoader] Error: File too small to be a valid ELF: " << path << "\n";
        return false;
    }

    std::vector<uint8_t> buffer(file_size);
    file.read(reinterpret_cast<char*>(buffer.data()), file_size);

    const auto* ehdr = reinterpret_cast<const Elf32_Ehdr*>(buffer.data());

    // Verify ELF Magic
    if (ehdr->e_ident[0] != 0x7F || ehdr->e_ident[1] != 'E' ||
        ehdr->e_ident[2] != 'L'  || ehdr->e_ident[3] != 'F') {
        std::cerr << "[ElfLoader] Error: Invalid ELF magic number\n";
        return false;
    }

    // Verify 32-bit (ELFCLASS32 = 1) and Little Endian (ELFDATA2LSB = 1)
    if (ehdr->e_ident[4] != 1 || ehdr->e_ident[5] != 1) {
        std::cerr << "[ElfLoader] Error: Only 32-bit little-endian ELF files supported\n";
        return false;
    }

    entrypoint = ehdr->e_entry;

    // Load Program Segments
    for (uint16_t i = 0; i < ehdr->e_phnum; ++i) {
        size_t ph_offset = ehdr->e_phoff + i * sizeof(Elf32_Phdr);
        if (ph_offset + sizeof(Elf32_Phdr) > file_size) break;

        const auto* phdr = reinterpret_cast<const Elf32_Phdr*>(buffer.data() + ph_offset);
        if (phdr->p_type != PT_LOAD) continue;

        uint32_t vaddr = phdr->p_vaddr;
        uint32_t offset = phdr->p_offset;
        uint32_t filesz = phdr->p_filesz;
        uint32_t memsz = phdr->p_memsz;

        if (vaddr < mem_base) continue;
        uint32_t ram_offset = vaddr - mem_base;

        if (ram_offset + memsz > memory.size()) {
            memory.resize(ram_offset + memsz, 0);
        }

        if (filesz > 0 && offset + filesz <= file_size) {
            std::memcpy(memory.data() + ram_offset, buffer.data() + offset, filesz);
        }
        if (memsz > filesz) {
            std::memset(memory.data() + ram_offset + filesz, 0, memsz - filesz);
        }
    }

    // Search Section Headers for Symbol Table to locate "tohost"
    tohost_addr = 0;
    if (ehdr->e_shoff > 0 && ehdr->e_shnum > 0) {
        for (uint16_t i = 0; i < ehdr->e_shnum; ++i) {
            size_t sh_offset = ehdr->e_shoff + i * sizeof(Elf32_Shdr);
            if (sh_offset + sizeof(Elf32_Shdr) > file_size) break;

            const auto* shdr = reinterpret_cast<const Elf32_Shdr*>(buffer.data() + sh_offset);
            if (shdr->sh_type == SHT_SYMTAB) {
                // Link points to associated string table
                uint32_t strtab_idx = shdr->sh_link;
                if (strtab_idx >= ehdr->e_shnum) continue;

                size_t strtab_sh_offset = ehdr->e_shoff + strtab_idx * sizeof(Elf32_Shdr);
                const auto* strtab_shdr = reinterpret_cast<const Elf32_Shdr*>(buffer.data() + strtab_sh_offset);

                const char* strtab = reinterpret_cast<const char*>(buffer.data() + strtab_shdr->sh_offset);
                size_t sym_count = shdr->sh_size / sizeof(Elf32_Sym);

                for (size_t s = 0; s < sym_count; ++s) {
                    const auto* sym = reinterpret_cast<const Elf32_Sym*>(
                        buffer.data() + shdr->sh_offset + s * sizeof(Elf32_Sym)
                    );
                    const char* name = strtab + sym->st_name;
                    if (std::strcmp(name, "tohost") == 0) {
                        tohost_addr = sym->st_value;
                        break;
                    }
                }
            }
        }
    }

    return true;
}

bool ElfLoader::load_hex(
    const std::string& path,
    std::vector<uint8_t>& memory,
    uint32_t mem_base
) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::cerr << "[ElfLoader] Error: Unable to open HEX file: " << path << "\n";
        return false;
    }

    std::string line;
    uint32_t cur_addr = mem_base;

    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#' || line[0] == '/') continue;

        if (line[0] == '@') {
            // Address specifier: @80000000
            cur_addr = std::stoul(line.substr(1), nullptr, 16);
            continue;
        }

        std::istringstream iss(line);
        std::string word;
        while (iss >> word) {
            uint32_t val = std::stoul(word, nullptr, 16);
            if (word.length() <= 2) {
                // Byte format
                if (cur_addr >= mem_base) {
                    uint32_t offset = cur_addr - mem_base;
                    if (offset >= memory.size()) memory.resize(offset + 4096, 0);
                    memory[offset] = static_cast<uint8_t>(val);
                }
                cur_addr += 1;
            } else {
                // 32-bit Word format (Little-Endian)
                if (cur_addr >= mem_base) {
                    uint32_t offset = cur_addr - mem_base;
                    if (offset + 4 > memory.size()) memory.resize(offset + 4096, 0);
                    memory[offset + 0] = static_cast<uint8_t>(val & 0xFF);
                    memory[offset + 1] = static_cast<uint8_t>((val >> 8) & 0xFF);
                    memory[offset + 2] = static_cast<uint8_t>((val >> 16) & 0xFF);
                    memory[offset + 3] = static_cast<uint8_t>((val >> 24) & 0xFF);
                }
                cur_addr += 4;
            }
        }
    }

    return true;
}

bool ElfLoader::load_bin(
    const std::string& path,
    std::vector<uint8_t>& memory,
    uint32_t mem_base,
    uint32_t load_offset
) {
    (void)mem_base;
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "[ElfLoader] Error: Unable to open binary file: " << path << "\n";
        return false;
    }

    file.seekg(0, std::ios::end);
    size_t size = file.tellg();
    file.seekg(0, std::ios::beg);

    if (load_offset + size > memory.size()) {
        memory.resize(load_offset + size, 0);
    }

    file.read(reinterpret_cast<char*>(memory.data() + load_offset), size);
    return true;
}

} // namespace talos
