#pragma once
/******************************************************************************
Based on:



Distributed as-is; no warranty is given.
******************************************************************************/
#include <Arduino.h>
namespace HomeAutomationTools {
    class HIH6130
    {
    public:
        HIH6130(byte address=0x27);	// Initialize HIH6130 sensor at given address
        void begin(void);  // Join I2C bus
        void end(void); // Get off I2C bus
        unsigned char GetReadings(float &humidity, float &tempC);

    protected:
        const int _address; // Address of Temperature sensor (0x27)
    };

}

