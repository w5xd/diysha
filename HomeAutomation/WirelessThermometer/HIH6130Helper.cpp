/******************************************************************************
based on:

SparkFunTMP102.cpp
SparkFunTMP102 Library Source File
Alex Wende @ SparkFun Electronics
Original Creation Date: April 29, 2016
https://github.com/sparkfun/Digital_Temperature_Sensor_Breakout_-_TMP102

******************************************************************************/
#include "HIH6130Helper.h"
#include <Wire.h>

namespace HomeAutomationTools {

    HIH6130::HIH6130(byte address)
    	: _address(address)
    {
    }

    void HIH6130::begin(void)
    {
        Wire.begin();  // Join I2C bus
    }

    unsigned char HIH6130::GetReadings(float &humidity, float &tempC)
    {
    	Wire.beginTransmission(_address); // start digitization
    	Wire.endTransmission();
    	delay(70); // spec is 60 msec measurement delay
    	Wire.requestFrom(_address, 4);
    	byte b0, b1, b2, b3;
    	b0 = Wire.read();
    	b1 = Wire.read();
    	b2 = Wire.read();
    	b3 = Wire.read();
    	unsigned char ret = (b0 >> 6) & 0x3;
    	uint16_t h = b0 & 0x3F;
    	h <<= 8;
    	h |= b1 & 0xFF;
    	humidity = static_cast<float>(h) * 100.f / static_cast<float>(0x3fff);
    	uint16_t t = b2;
    	t <<= 8;
    	t |= b3 & 0xFF0;
    	t >>= 2;
    	tempC = -40 + static_cast<float>(t) * 165.f / static_cast<float>(0x3fff);
    	return ret;
    }


    void HIH6130::end()
    {
        Wire.end();
        pinMode(PIN_WIRE_SCL, INPUT);
        digitalWrite(PIN_WIRE_SCL, LOW);
        pinMode(PIN_WIRE_SDA, INPUT);
        digitalWrite(PIN_WIRE_SDA, LOW);
    }



}
