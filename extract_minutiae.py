#!/usr/bin/env python3
"""
===============================================================================
Script Name: extract_minutiae.py
Description: Off-Chip Minutiae Feature Extraction Pipeline for Edge Biometric SoC
Dependencies: opencv-python, numpy

Algorithmic Pipeline:
  1. Grayscale loading and Otsu automatic threshold binarization.
  2. Morphological skeletonization/thinning down to 1-pixel-wide ridge structures.
  3. Rutovitz Crossing Number (Cn) detection for minutiae classification:
     - Cn = 1 => Ridge Termination
     - Cn = 3 => Ridge Bifurcation
  4. 4D Feature Quantification:
     - Central X [0..255] & Central Y [0..255] spatial centroid
     - Local Orientation Angle Theta [0..255] via Sobel gradient fields
     - Local Ridge Density [0..255] via skeleton pixel ratio
  5. Packing into 32-bit unsigned integers:
     packed_vector = (X << 24) | (Y << 16) | (Theta << 8) | Density
  6. Formatted console output ready to paste into secure_template_vault.v:
     memory[i] = 32'hXXXXXXXX; // <filename>.bmp
===============================================================================
"""

import cv2
import numpy as np
import sys
import os
import glob


def rutovitz_crossing_number(neighborhood_3x3):
    """
    Computes Rutovitz Crossing Number Cn for a 3x3 binary pixel window.
    Cn = 0.5 * sum(|P_i - P_{i+1}|) for i in 1..8 (with P_9 = P_1).
    Neighbors ordered clockwise:
        P9 P2 P3
        P8 P1 P4
        P7 P6 P5
    """
    p = neighborhood_3x3.astype(int)
    # Binary 0/1 values
    p = (p > 0).astype(int)
    
    # 8-neighbors sequence clockwise: P2, P3, P4, P5, P6, P7, P8, P9, P2
    n = [p[0, 1], p[0, 2], p[1, 2], p[2, 2], p[2, 1], p[2, 0], p[1, 0], p[0, 0], p[0, 1]]
    
    cn = 0.5 * sum(abs(n[i] - n[i+1]) for i in range(8))
    return int(cn)


def morph_thinning(binary_image):
    """
    Iterative Morphological Thinning (Zhang-Suen equivalent)
    Reduces ridges down to 1-pixel-wide skeleton.
    """
    img = binary_image.copy()
    img = (img > 0).astype(np.uint8)
    skeleton = np.zeros(img.shape, np.uint8)
    element = cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))
    
    done = False
    while not done:
        eroded = cv2.erode(img, element)
        temp = cv2.dilate(eroded, element)
        temp = cv2.subtract(img, temp)
        skeleton = cv2.bitwise_or(skeleton, temp)
        img = eroded.copy()
        
        if cv2.countNonZero(img) == 0:
            done = True
            
    return skeleton * 255


def extract_minutiae_from_image(image_path):
    """
    Ingests a single fingerprint image (.bmp) and extracts packed 32-bit hardware vector.
    """
    # -------------------------------------------------------------------------
    # STEP 1: Grayscale Loading and Otsu Binarization
    # -------------------------------------------------------------------------
    img_gray = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img_gray is None:
        raise FileNotFoundError(f"Unable to read image file: {image_path}")

    # Standardize image spatial dimensions to 256x256 for 8-bit hardware alignment
    img_resized = cv2.resize(img_gray, (256, 256))

    # Otsu automatic thresholding (Inverted: ridges = 255, valleys = 0)
    _, img_otsu = cv2.threshold(
        img_resized, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )

    # -------------------------------------------------------------------------
    # STEP 2: Morphological Skeletonization / Thinning (1-pixel-wide ridges)
    # -------------------------------------------------------------------------
    skeleton = morph_thinning(img_otsu)

    # -------------------------------------------------------------------------
    # STEP 3: Rutovitz Crossing Number (Cn) Minutiae Detection
    # -------------------------------------------------------------------------
    skel_binary = (skeleton > 0).astype(np.uint8)
    terminations = []
    bifurcations = []

    h, w = skel_binary.shape
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if skel_binary[y, x] == 1:
                patch = skel_binary[y-1:y+2, x-1:x+2]
                cn = rutovitz_crossing_number(patch)
                if cn == 1:
                    terminations.append((x, y))
                elif cn == 3:
                    bifurcations.append((x, y))

    all_minutiae = terminations + bifurcations

    # -------------------------------------------------------------------------
    # STEP 4: Feature Quantification (X, Y, Theta, Density)
    # -------------------------------------------------------------------------
    # A) Central X and Central Y (0..255)
    if len(all_minutiae) > 0:
        avg_x = int(np.mean([pt[0] for pt in all_minutiae]))
        avg_y = int(np.mean([pt[1] for pt in all_minutiae]))
    else:
        # Fallback to image moments centroid if no minutiae detected
        M = cv2.moments(img_otsu)
        if M['m00'] != 0:
            avg_x = int(M['m10'] / M['m00'])
            avg_y = int(M['m01'] / M['m00'])
        else:
            avg_x, avg_y = 128, 128

    # Clamp X, Y to strictly [0..255]
    X_8bit = max(0, min(255, avg_x))
    Y_8bit = max(0, min(255, avg_y))

    # B) Local Orientation Angle Theta (0..255) via Sobel Gradients
    sobel_x = cv2.Sobel(img_resized, cv2.CV_64F, 1, 0, ksize=3)
    sobel_y = cv2.Sobel(img_resized, cv2.CV_64F, 0, 1, ksize=3)
    mean_gx = np.mean(sobel_x)
    mean_gy = np.mean(sobel_y)
    
    angle_rad = np.arctan2(mean_gy, mean_gx) # range [-pi, +pi]
    # Map [-pi, +pi] linearly to 8-bit [0..255] range
    theta_8bit = int(((angle_rad + np.pi) / (2.0 * np.pi)) * 255.0)
    theta_8bit = max(0, min(255, theta_8bit))

    # C) Local Ridge Density (0..255)
    total_ridge_pixels = np.count_nonzero(skel_binary)
    # Normalize pixel ratio (max 256*256 = 65536) to [0..255]
    density_ratio = total_ridge_pixels / (256.0 * 256.0)
    density_8bit = int(min(255, density_ratio * 255.0 * 8.0)) # Scaled for dynamic range

    # -------------------------------------------------------------------------
    # STEP 5: Packing into 32-Bit Unsigned Integer Vector
    # Format: (X << 24) | (Y << 16) | (Theta << 8) | Density
    # -------------------------------------------------------------------------
    packed_32bit = ((X_8bit & 0xFF) << 24) | \
                   ((Y_8bit & 0xFF) << 16) | \
                   ((theta_8bit & 0xFF) << 8) | \
                   (density_8bit & 0xFF)

    filename = os.path.basename(image_path)
    verilog_code = f"memory[i] = 32'h{packed_32bit:08X}; // {filename}"

    return {
        'filename':     filename,
        'X':            X_8bit,
        'Y':            Y_8bit,
        'Theta':        theta_8bit,
        'Density':      density_8bit,
        'packed_hex':   f"32'h{packed_32bit:08X}",
        'packed_int':   packed_32bit,
        'verilog_line': verilog_code,
        'terminations': len(terminations),
        'bifurcations': len(bifurcations)
    }


def main():
    print("==========================================================================")
    print("      OFF-CHIP MINUTIAE FEATURE EXTRACTION PIPELINE (SOCOFing)            ")
    print("==========================================================================")

    # Determine input target file or folder
    if len(sys.argv) > 1:
        target_path = sys.argv[1]
    else:
        # Default scan directory
        target_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dataset")

    image_files = []
    if os.path.isfile(target_path):
        image_files = [target_path]
    elif os.path.isdir(target_path):
        for ext in ("*.bmp", "*.png", "*.tif", "*.jpg", "*.BMP"):
            image_files.extend(glob.glob(os.path.join(target_path, "**", ext), recursive=True))
    
    if not image_files:
        print(f"[!] No image files found at target path: {target_path}")
        print("[!] Generating synthetic demonstration vector for validation...")
        demo_vector = extract_minutiae_synthetic_demo()
        return

    print(f"[+] Processing {len(image_files)} fingerprint image(s)...\n")

    results = []
    for idx, fpath in enumerate(image_files):
        try:
            res = extract_minutiae_from_image(fpath)
            results.append(res)
            print(f"  [{idx+1}/{len(image_files)}] {res['filename']}")
            print(f"      Features: Centroid=({res['X']}, {res['Y']}), θ={res['Theta']}, Density={res['Density']}")
            print(f"      Minutiae: Terminations={res['terminations']}, Bifurcations={res['bifurcations']}")
            print(f"      Hardware Hex: {res['packed_hex']}")
            print(f"      Verilog Line: {res['verilog_line']}\n")
        except Exception as err:
            print(f"  [!] Failed to process {fpath}: {err}")

    if results:
        print("\n==========================================================================")
        print("  VERILOG ENROLLED TEMPLATE INITIALIZERS (Paste into secure_template_vault.v) ")
        print("==========================================================================")
        for i, res in enumerate(results[:4]):
            print(f"        memory[{i}] = {res['packed_hex']}; // {res['filename']}")
        print("==========================================================================\n")


def extract_minutiae_synthetic_demo():
    """Generates a synthetic 256x256 test image and runs extraction."""
    synth_img = np.zeros((256, 256), dtype=np.uint8)
    for r in range(20, 240, 12):
        cv2.circle(synth_img, (128, 128), r, 255, 3)
    
    demo_path = "/tmp/synthetic_fingerprint.bmp"
    cv2.imwrite(demo_path, synth_img)
    res = extract_minutiae_from_image(demo_path)
    
    print("\n--- SYNTHETIC DEMONSTRATION RUN ---")
    print(f"Image: {res['filename']}")
    print(f"Features: X={res['X']}, Y={res['Y']}, Theta={res['Theta']}, Density={res['Density']}")
    print(f"Verilog Format: {res['verilog_line']}\n")
    return res


if __name__ == "__main__":
    main()
