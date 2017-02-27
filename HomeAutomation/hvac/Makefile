
all: procEventLog procWeatherGov procFurnace procWirelessGateway

procEventLog: procEventLog.cpp
	g++ -o procEventLog procEventLog.cpp  -lboost_date_time

procWeatherGov: procWeatherGov.cpp weather_gov.h
	g++ -o procWeatherGov procWeatherGov.cpp -lboost_date_time

procFurnace: procFurnace.cpp weather_gov.h
	g++ -o procFurnace procFurnace.cpp

procWirelessGateway: procWirelessGateway.o PlmMonitorLinux.o
	g++ -o procWirelessGateway procWirelessGateway.o PlmMonitorLinux.o

procWirelessGateway.o: procWirelessGateway.cpp
	g++ -c -std=c++11 -DLINUX32 -I.. -o procWirelessGateway.o procWirelessGateway.cpp

PlmMonitorLinux.o: ../w5xdInsteon/impl/PlmMonitorLinux.cpp
	g++ -c -DLINUX32 -o PlmMonitorLinux.o ../w5xdInsteon/impl/PlmMonitorLinux.cpp
