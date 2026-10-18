// -----------------------------------------------------------------------------
// mt_dpi_mem.cpp -- DPI memory used by the standalone mt_cvxif_shim testbench.
//
// Mirrors the contract that npc/csrc/wave/mem.cpp will provide for the JYD
// integration: the accelerator DMA and the CPU both address the miniTensor
// buffer through the uncached DRAM alias window (0x8033_0000), and the helper
// normalises it by clearing address bit 21 to reach the physical bytes.
//
//   alias 0x8033_0000 + off  ->  physical 0x8013_0000 + off
// -----------------------------------------------------------------------------
#include <cstdio>
#include <cstdint>
#include <cstring>

#define MT_BUF_ALIAS_BASE 0x80330000u
#define MT_BUF_PHYS_BASE  0x80130000u
#define MT_BUF_SIZE       0x00010000u
#define MT_ALIAS_MASK     0x00200000u

static uint8_t g_buf[MT_BUF_SIZE];

static uint8_t *mt_phys(uint32_t alias_addr, uint32_t len)
{
    uint32_t a = alias_addr & ~MT_ALIAS_MASK;
    if (a < MT_BUF_PHYS_BASE || (a + len) > (MT_BUF_PHYS_BASE + MT_BUF_SIZE)) {
        std::fprintf(stderr, "[mt_dpi] address 0x%08x (phys 0x%08x) outside MT buffer\n",
                     alias_addr, a);
        return nullptr;
    }
    return g_buf + (a - MT_BUF_PHYS_BASE);
}

extern "C" void mt_dma_read(int addr, int *w0, int *w1, int *w2, int *w3)
{
    uint8_t *p = mt_phys((uint32_t)addr, 16u);
    if (!p) { *w0 = *w1 = *w2 = *w3 = 0; return; }
    uint32_t words[4];
    std::memcpy(words, p, sizeof(words));
    *w0 = (int)words[0]; *w1 = (int)words[1];
    *w2 = (int)words[2]; *w3 = (int)words[3];
}

extern "C" void mt_dma_write(int addr, int w0, int w1, int w2, int w3)
{
    uint8_t *p = mt_phys((uint32_t)addr, 16u);
    if (!p) return;
    uint32_t words[4] = {(uint32_t)w0, (uint32_t)w1, (uint32_t)w2, (uint32_t)w3};
    std::memcpy(p, words, sizeof(words));
}

// Testbench-only helpers for preloading and checking the buffer.
extern "C" void mt_mem_poke(int addr, int data)
{
    uint8_t *p = mt_phys((uint32_t)addr, 4u);
    if (!p) return;
    uint32_t w = (uint32_t)data;
    std::memcpy(p, &w, sizeof(w));
}

extern "C" int mt_mem_peek(int addr)
{
    uint8_t *p = mt_phys((uint32_t)addr, 4u);
    if (!p) return 0;
    uint32_t w;
    std::memcpy(&w, p, sizeof(w));
    return (int)w;
}

extern "C" void mt_mem_fill(int addr, int byte_value, int nbytes)
{
    uint8_t *p = mt_phys((uint32_t)addr, (uint32_t)nbytes);
    if (!p) return;
    std::memset(p, byte_value, (size_t)nbytes);
}
