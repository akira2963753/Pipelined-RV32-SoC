# Cache IP

This directory contains the active ASIC-oriented cache RTL and its VCS verification environment.

## Configuration

- I-Cache and D-Cache are 4 KiB, two-way set associative caches.
- Each cache has 64 sets and a 32-byte cache line made of eight 32-bit AXI beats.
- I-Cache is read-only and can accept one hit request per cycle after pipeline fill.
- D-Cache uses write-through and no-write-allocate policy with four byte strobes.
- Both CPU-facing interfaces use independent request and response ready-valid handshakes.

## Directory Layout

```text
CACHE/
|-- 00_TESTBED/
|   |-- TESTBED.sv
|   |-- PATTERN.sv
|   `-- makefile
|-- 01_RTL/
|   |-- I_Cache.sv
|   |-- D_Cache.sv
|   |-- Cache_Top.sv
|   |-- file.f
|   `-- 01_run
`-- legacy/
    |-- I-CACHE/             # Legacy implementation, not in file.f
    |-- D-CACHE/             # Legacy implementation, not in file.f
    `-- Constraint.xdc       # Legacy Vivado constraint
```

## VCS Run

Run the complete compile and simulation flow from `01_RTL`:

```sh
sh 01_run
```

Compile once and rerun with a chosen seed:

```sh
make -f ../00_TESTBED/makefile compile
make -f ../00_TESTBED/makefile run SEED=1
```

Generated logs and the simulator executable are written under `00_TESTBED/build/`. The FSDB waveform is written to `00_TESTBED/TESTBED.fsdb`.

## Verification Scope

- I-Cache cold miss, line hit, back-to-back hit throughput, LRU replacement and invalidation.
- D-Cache load hit/miss, write hit, write miss, write-through and no-write-allocate behavior.
- Byte write strobes, CPU response backpressure and AXI channel backpressure.
- AXI read/write error propagation to the CPU response.
- SVA payload-stability, AXI attribute and reset checks.
