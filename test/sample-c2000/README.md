# Sample C2000 Project

This is a minimal TI C2000 project for testing the GitHub Action.

## Project Details

- **Target Device**: TMS320F28377D
- **Configuration**: Debug
- **Toolchain**: TI C2000 Compiler
- **Purpose**: Verify that the action can successfully import and build a CCS project

## Files

- `main.c` - Simple counter program
- `.project` - Eclipse project configuration
- `.cproject` - CDT build configuration

## Usage in Tests

This project is used by the `test-versions.yml` workflow to verify that each CCS version can:
1. Import the project
2. Build it successfully
3. Generate output artifacts
