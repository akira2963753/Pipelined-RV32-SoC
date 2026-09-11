#!/usr/bin/env python3
"""
RISC-V CPU Automated Verification Script
Converts test cases, generates golden reference, and verifies simulation results
"""

import sys
import os
import subprocess
from pathlib import Path

# ANSI color codes for terminal output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

def print_header(title):
    """Print a formatted header"""
    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{title.center(60)}{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*60}{Colors.RESET}\n")

def check_testcase_exists(testcase_num):
    """Check if the test case file exists"""
    testcase_file = f"Pattern/TestCase{testcase_num}.dat"
    return os.path.exists(testcase_file)

def convert_testcase(testcase_num):
    """Convert test case to IM.dat using Instr_Transfer.py"""
    print(f"{Colors.CYAN}[Step 1/2] Converting TestCase{testcase_num}.dat to IM.dat...{Colors.RESET}")

    testcase_file = f"Pattern/TestCase{testcase_num}.dat"

    if not os.path.exists(testcase_file):
        print(f"{Colors.RED}Error: {testcase_file} not found!{Colors.RESET}")
        return False

    try:
        # Run Instr_Transfer.py
        result = subprocess.run(
            ['python', 'Pattern/Instr_Transfer.py', testcase_file],
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='ignore'  # 忽略編碼錯誤
        )

        if result.returncode != 0:
            print(f"{Colors.RED}Error during conversion:{Colors.RESET}")
            print(result.stderr)
            return False

        # Move IM.dat to Testbench directory
        if os.path.exists('IM.dat'):
            import shutil
            shutil.move('IM.dat', 'Testbench/IM.dat')
            print(f"{Colors.GREEN}✓ Successfully converted and moved to Testbench/IM.dat{Colors.RESET}")
        else:
            print(f"{Colors.RED}Error: IM.dat was not generated{Colors.RESET}")
            return False

        return True

    except Exception as e:
        print(f"{Colors.RED}Error running Instr_Transfer.py: {e}{Colors.RESET}")
        return False

def generate_golden():
    """Generate golden reference using Golden_Result.py"""
    print(f"\n{Colors.CYAN}[Step 2/2] Generating golden reference...{Colors.RESET}")

    if not os.path.exists('Testbench/Golden_Result.py'):
        print(f"{Colors.RED}Error: Testbench/Golden_Result.py not found!{Colors.RESET}")
        return False

    try:
        # Change to Testbench directory and run Golden_Result.py
        result = subprocess.run(
            ['python', 'Golden_Result.py'],
            cwd='Testbench',
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='ignore'  # 忽略編碼錯誤
        )

        if result.returncode != 0:
            print(f"{Colors.RED}Error generating golden reference:{Colors.RESET}")
            print(result.stderr)
            return False

        # Check if golden files were created
        if os.path.exists('Testbench/RF.golden') and os.path.exists('Testbench/DM.golden'):
            print(f"{Colors.GREEN}✓ Successfully generated RF.golden and DM.golden{Colors.RESET}")
            return True
        else:
            print(f"{Colors.RED}Error: Golden files were not generated{Colors.RESET}")
            return False

    except Exception as e:
        print(f"{Colors.RED}Error running Golden_Result.py: {e}{Colors.RESET}")
        return False

def parse_file(filename):
    """
    Parse output file with format: [Index] hexvalue
    Returns dictionary: {index: value}
    """
    data = {}
    if not os.path.exists(filename):
        return None

    with open(filename, 'r', encoding='latin-1') as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith('//'):
                continue

            # Parse format: [Index] hexvalue
            if line.startswith('['):
                try:
                    # Extract index and value
                    parts = line.split(']')
                    index = int(parts[0][1:])  # Remove '[' and convert to int
                    value = parts[1].strip()   # Get hex value
                    data[index] = value.lower()  # Normalize to lowercase
                except (IndexError, ValueError) as e:
                    print(f"{Colors.YELLOW}Warning: Could not parse line '{line}' in {filename}{Colors.RESET}")
                    continue

    return data

def compare_data(sim_data, golden_data, name):
    """
    Compare simulation output with golden reference
    Returns (pass, mismatch_count, details)
    """
    if sim_data is None:
        return False, 0, f"{name} simulation output not found"

    if golden_data is None:
        return False, 0, f"{name} golden reference not found"

    # Get all indices from both datasets
    all_indices = set(sim_data.keys()) | set(golden_data.keys())

    mismatches = []
    for idx in sorted(all_indices):
        sim_val = sim_data.get(idx, 'MISSING')
        golden_val = golden_data.get(idx, 'MISSING')

        if sim_val != golden_val:
            mismatches.append({
                'index': idx,
                'simulation': sim_val,
                'golden': golden_val
            })

    if mismatches:
        details = f"\n  {Colors.RED}Found {len(mismatches)} mismatch(es):{Colors.RESET}\n"
        for mismatch in mismatches:
            details += f"    [{mismatch['index']}] "
            details += f"Simulation: {mismatch['simulation']:<12} "
            details += f"Golden: {mismatch['golden']:<12}\n"
        return False, len(mismatches), details

    return True, 0, ""

def verify():
    """
    Verification function
    """
    print_header("Verification Results")

    # Change to Testbench directory
    os.chdir('Testbench')

    # Check for required files
    files_to_check = ['RF.out', 'RF.golden', 'DM.out', 'DM.golden']
    missing_files = []

    for filename in files_to_check:
        if not os.path.exists(filename):
            missing_files.append(filename)

    if missing_files:
        print(f"{Colors.RED}Error: Missing required files:{Colors.RESET}")
        for filename in missing_files:
            print(f"  - {filename}")
        print(f"\n{Colors.YELLOW}Please run the RTL simulation first to generate RF.out and DM.out.{Colors.RESET}")
        os.chdir('..')
        return False

    # Parse Register File outputs
    print(f"{Colors.BLUE}[1/4] Loading Register File simulation output...{Colors.RESET}")
    rf_sim = parse_file('RF.out')
    print(f"      Loaded {len(rf_sim) if rf_sim else 0} register values")

    print(f"{Colors.BLUE}[2/4] Loading Register File golden reference...{Colors.RESET}")
    rf_golden = parse_file('RF.golden')
    print(f"      Loaded {len(rf_golden) if rf_golden else 0} register values")

    # Parse Data Memory outputs
    print(f"{Colors.BLUE}[3/4] Loading Data Memory simulation output...{Colors.RESET}")
    dm_sim = parse_file('DM.out')
    print(f"      Loaded {len(dm_sim) if dm_sim else 0} memory values")

    print(f"{Colors.BLUE}[4/4] Loading Data Memory golden reference...{Colors.RESET}")
    dm_golden = parse_file('DM.golden')
    print(f"      Loaded {len(dm_golden) if dm_golden else 0} memory values")

    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{'Comparison Results'.center(60)}{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*60}{Colors.RESET}\n")

    # Compare Register File
    print(f"{Colors.BOLD}Register File (RF) Verification:{Colors.RESET}")
    rf_pass, rf_mismatches, rf_details = compare_data(rf_sim, rf_golden, "RF")

    if rf_pass:
        print(f"  {Colors.GREEN}✓ PASSED{Colors.RESET} - All {len(rf_sim)} registers match")
    else:
        print(f"  {Colors.RED}✗ FAILED{Colors.RESET}{rf_details}")

    # Compare Data Memory
    print(f"\n{Colors.BOLD}Data Memory (DM) Verification:{Colors.RESET}")
    dm_pass, dm_mismatches, dm_details = compare_data(dm_sim, dm_golden, "DM")

    if dm_pass:
        print(f"  {Colors.GREEN}✓ PASSED{Colors.RESET} - All {len(dm_sim)} memory locations match")
    else:
        print(f"  {Colors.RED}✗ FAILED{Colors.RESET}{dm_details}")

    # Final summary
    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{'Summary'.center(60)}{Colors.RESET}")
    print(f"{Colors.BOLD}{'='*60}{Colors.RESET}\n")

    total_tests = 2
    passed_tests = sum([rf_pass, dm_pass])

    os.chdir('..')

    if passed_tests == total_tests:
        print(f"  {Colors.GREEN}{Colors.BOLD}ALL TESTS PASSED!{Colors.RESET}")
        print(f"  {Colors.GREEN}Your CPU simulation matches the golden reference perfectly.{Colors.RESET}\n")
        return True
    else:
        print(f"  {Colors.RED}Tests Passed: {passed_tests}/{total_tests}{Colors.RESET}")
        print(f"  {Colors.RED}Tests Failed: {total_tests - passed_tests}/{total_tests}{Colors.RESET}")
        total_mismatches = rf_mismatches + dm_mismatches
        print(f"  {Colors.RED}Total Mismatches: {total_mismatches}{Colors.RESET}\n")
        return False

def main():
    """
    Main entry point
    """
    try:
        print_header("RISC-V CPU Automated Verification")

        # ==================== Stage 1: Test Case Conversion ====================
        print(f"{Colors.BOLD}Stage 1: Test Case Conversion & Golden Generation{Colors.RESET}\n")

        # List available test cases
        print(f"{Colors.CYAN}Available Test Cases:{Colors.RESET}")
        for i in range(1, 13):
            if check_testcase_exists(i):
                print(f"  [{i}] TestCase{i}.dat ✓")
            else:
                print(f"  [{i}] TestCase{i}.dat {Colors.RED}(not found){Colors.RESET}")

        # Get user input
        while True:
            try:
                testcase_input = input(f"\n{Colors.BOLD}Which test case do you want to convert? [1-12]: {Colors.RESET}").strip()
                testcase_num = int(testcase_input)

                if 1 <= testcase_num <= 12:
                    if check_testcase_exists(testcase_num):
                        break
                    else:
                        print(f"{Colors.RED}TestCase{testcase_num}.dat not found. Please choose another.{Colors.RESET}")
                else:
                    print(f"{Colors.RED}Please enter a number between 1 and 12.{Colors.RESET}")
            except ValueError:
                print(f"{Colors.RED}Invalid input. Please enter a number.{Colors.RESET}")
            except KeyboardInterrupt:
                print(f"\n{Colors.YELLOW}Operation cancelled by user.{Colors.RESET}")
                return

        # Convert test case
        print()
        if not convert_testcase(testcase_num):
            print(f"\n{Colors.RED}Failed to convert test case. Exiting.{Colors.RESET}")
            sys.exit(1)

        # Generate golden reference
        if not generate_golden():
            print(f"\n{Colors.RED}Failed to generate golden reference. Exiting.{Colors.RESET}")
            sys.exit(1)

        print(f"\n{Colors.GREEN}{Colors.BOLD}✓ Stage 1 completed successfully!{Colors.RESET}")
        print(f"{Colors.GREEN}  - IM.dat generated in Testbench/{Colors.RESET}")
        print(f"{Colors.GREEN}  - RF.golden and DM.golden generated in Testbench/{Colors.RESET}\n")

        # ==================== Stage 2: Verification ====================
        print(f"{Colors.BOLD}Stage 2: Verification{Colors.RESET}\n")

        # Ask if user wants to verify
        while True:
            verify_input = input(f"{Colors.BOLD}Do you want to start verification? [y/n]: {Colors.RESET}").strip().lower()

            if verify_input in ['y', 'yes']:
                print()
                success = verify()
                sys.exit(0 if success else 1)
            elif verify_input in ['n', 'no']:
                print(f"\n{Colors.YELLOW}Verification skipped.{Colors.RESET}")
                print(f"{Colors.YELLOW}You can run RTL simulation now and then run this script again for verification.{Colors.RESET}\n")
                sys.exit(0)
            else:
                print(f"{Colors.RED}Please enter 'y' or 'n'.{Colors.RESET}")

    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Operation interrupted by user.{Colors.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Error: {e}{Colors.RESET}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
