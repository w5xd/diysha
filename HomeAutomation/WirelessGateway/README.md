This is an Arduino sketch implementing a USB to wireless gateway. The
hardware is an Arduino UNO wired with the RFM69 breakout from Sparkfun.
https://learn.sparkfun.com/tutorials/rfm69hcw-hookup-guide

The gateway is designed to store and forward information in both directions: serial-to-RF and RF-to-serial. For that reason, the RESET EN jumper on the UNO must be removed. In current production, that means using a hobby knife to cut the so-labeled trace.
