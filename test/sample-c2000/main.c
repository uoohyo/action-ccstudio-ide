/*
 * Simple C2000 Sample Project
 * Minimal project for testing CCS build in GitHub Actions
 */

#include <stdint.h>

// Global variables
volatile uint16_t counter = 0;

// Main function
void main(void)
{
    // Initialize
    counter = 0;

    // Simple loop
    while(1)
    {
        counter++;

        // Simple delay
        __delay_cycles(1000000);
    }
}

// End of file
