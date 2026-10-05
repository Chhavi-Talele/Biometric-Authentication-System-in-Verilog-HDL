# Complete Hardware-Accelerated Edge Biometric Authentication System-on-Chip (SoC)

Production-grade, synthesizable implementation of a **Tamper-Resilient Edge Biometric Authentication System-on-Chip (SoC)** in IEEE 1364-2001 Verilog HDL, targeted for AMD Vivado (Artix-7 `xc7a35tcsg324-1` FPGA), paired with an off-chip minutiae feature extraction pipeline in Python.

---

## 🌟 Architectural Overview

```
                     +-------------------------------------------------------------+
                     |                     biometric_top.v                         |
                     +-------------------------------------------------------------+
                                                    |
     +-----------------------+                      |                      +------------------------+
     |   quality_analyzer    |                      |                      |  threshold_calculator  |
     +-----------------------+                      |                      +------------------------+
     | Q = (C+U)/2 - N/2     |                      |                      | T(Q) = 8 + ((255-Q)>>4)|
     | Grade: 11, 10, 01, 00 |----------------------+--------------------->| Saturate at T_max = 28 |
     +-----------------------+                      |                      +------------------------+
                |                                   |                                   |
                | quality_acceptable                | dynamic_threshold                 | dynamic_threshold
                v                                   v                                   v
     +----------------------------------------------------------------------------------------------+
     |                                      matcher_engine                                          |
     | D = |X_scan - X_stored| + |Y_scan - Y_stored| + |Theta_scan - Theta_stored| + |Density_scan - Density_stored|
     +----------------------------------------------------------------------------------------------+
                                                    |
                                                    | is_match
                                                    v
     +-----------------------+                      |                      +------------------------+
     |  secure_template_vault|                      |                      |     auth_controller    |
     +-----------------------+                      |                      +------------------------+
     | 4 Enrolled Templates  |<--------------------------------------------| 7-State Security FSM   |
     | 3-Pass Zeroization    |         zeroize_trigger (Purge Memory)      | 3-Strike Lockout       |
     | (1s -> 0s -> PRNG)   |-------------------------------------------->| Irreversible Lockdown  |
     +-----------------------+                   wipe_done                 +------------------------+
```

---

## ⚙️ Core Hardware Modules

1. **`quality_analyzer.v`**: Multi-factor quality fusion engine calculating $Q = \left(\frac{\text{contrast} + \text{uniformity}}{2}\right) - \left(\frac{\text{noise}}{2}\right)$. Features hardware grade decoding (Pristine, Good, Degraded, Reject/Spoof) and an instant anti-spoof auto-rejection guard floor for $Q < 70$.
2. **`threshold_calculator.v`**: Divider-free continuous dynamic threshold engine computing $T(Q) = 8 + ((255 - Q) \gg 4)$, saturated at $T_{\text{max}} = 28$.
3. **`secure_template_vault.v`**: Secure template memory holding 4 enrolled users' 32-bit biometric vectors ($\{X, Y, \Theta, \text{Density}\}$). Features an autonomous 3-Pass DoD 5220.22-M / NIST SP 800-88 compliant anti-remanence zeroization engine using a 32-bit Galois LFSR ($x^{32} + x^{22} + x^2 + x^1 + 1$).
4. **`matcher_engine.v`**: 4-Dimensional spatial Manhattan distance accelerator computing $D = \vert\Delta X\vert + \vert\Delta Y\vert + \vert\Delta \Theta\vert + \vert\Delta \text{Density}\vert$.
5. **`auth_controller.v`**: 7-State Security Finite State Machine (`S_IDLE`, `S_FETCH`, `S_COMPARE`, `S_EVALUATE`, `S_PENALTY`, `S_ZEROIZE`, `S_LOCKDOWN`) enforcing progressive cooldown lockout, physical anti-tamper fast paths, 3-strike self-destruct triggers, and irreversible silicon lockdown.
6. **`biometric_top.v`**: Top-level System-on-Chip structural wrapper routing all inter-module buses cleanly.
7. **`tb_biometric_top.v`**: Self-checking testbench driving a 100 MHz system clock and verifying 7 corner-case attack scenarios.

---

## 🐍 Off-Chip Minutiae Feature Extraction Pipeline

- **`extract_minutiae.py`**: Python script utilizing OpenCV and NumPy to ingest raw fingerprint images (`.bmp` SOCOFing dataset) and perform:
  1. Grayscale loading & Otsu automatic threshold binarization.
  2. Morphological thinning/skeletonization to 1-pixel-wide ridges.
  3. Rutovitz Crossing Number ($C_n$) minutiae classification ($C_n = 1$ termination, $C_n = 3$ bifurcation).
  4. 4D feature quantification ($X$, $Y$, $\Theta$, Density).
  5. 32-bit unsigned integer packing: `(X << 24) | (Y << 16) | (Theta << 8) | Density`.
  6. Direct Verilog initialiser output formatting.

---

## 🚀 Execution & Verification

### Running Testbench in Icarus Verilog
```bash
iverilog -o sim_tb tb_biometric_top.v biometric_top.v quality_analyzer.v threshold_calculator.v secure_template_vault.v matcher_engine.v auth_controller.v
vvp sim_tb
```

### Running Feature Extractor in Python
```bash
python3 extract_minutiae.py <path_to_fingerprint.bmp>
```
