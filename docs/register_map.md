# ARES-P4 register map

## CLINT (0x0001_0000)

- 0x0000 + 4*h : msip[h], write bit0 to set/clear software interrupt.
- 0x4000 + 8*h : mtimecmp[h] low/high.
- 0xBFF8 / 0xBFFC : mtime low/high.

## PLIC (0x0002_0000)

- 0x0000 + 4*s : source priority.
- 0x1000 : pending.
- 0x2000 + ctx*0x80 + 4*s : enable for context ctx.
- 0x200000 + ctx*0x1000 : threshold.
- 0x200004 + ctx*0x1000 : claim/complete.
- Sources: 0 UART, 1 GPIO, 2 SPI, 3 I2C, 4 SD, 5 video vsync,
  6 DMA, 7 mailbox, 8 barrier, 9-12 miniTensor 0-3, 13 GbE.

## Mailbox / barrier (0x0003_0000)

- 0x0000 + h*0x40 + s*4 : 16 slots per hart.
- 0x1000 + h*4 : doorbell set/read-clear.
- 0x2000 : barrier write (hart bit), read hit flag.
- 0x2004 : barrier status / reset.

## UART (0xD000_0000)

- 0x00 TX write / RX read.
- 0x04 status: bit0 tx_ready, bit1 rx_valid, bit2 tx_busy.
- 0x08 control: bit0 enable, bit1 rx irq, bit2 tx irq.
- 0x0C baud divisor.
- 0x14 scratch ('UART').

## GPIO (0xD000_1000)

- 0x00 input, 0x04 output, 0x08 direction, 0x0C irq enable, 0x10 irq status.

## SPI (0xD000_2000)

- 0x00 TX data (write starts), 0x04 RX data, 0x08 control,
  0x0C status, 0x10 clock divider.

## I2C / SD / GbE stubs (0xD000_3000 / 0x4000 / 0x5000)

- 0x00 present, 0x04 status, 0x08 scratch.

## Video (0xD000_6000)

- 0x00 control: bit0 enable, bit1 test pattern, bit2 OSD, bit3 capture.
- 0x04 frame base (reserved for capture/scaler).
- 0x08 status: vsync/hsync/de/vsync_irq.
- 0x0C frame counter.
- 0x10 + 16*n : OSD box n:
  - +0x0 x0[15:0] / y0[31:16]
  - +0x4 x1[15:0] / y1[31:16]
  - +0x8 colour R[7:0] G[15:8] B[23:16]
  - +0xC bit0 enable

## miniTensor (0xE000_0000 + 0x1000*h)

- 0x00 INSTR, 0x04 RS1, 0x08 RS2, 0x0C KICK,
  0x10 STATUS (bit0 busy, bit1 done, bit2 err, bit3 accept_err, bit4 kick_err),
  0x14 RESULT.

## Debug (0xF000_0000)

- 0x00 returns 'ARES' (0x4152_4553).
