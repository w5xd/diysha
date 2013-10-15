
all: procEventLog procWeatherGov procFurnace

procEventLog: procEventLog.cpp
	g++ -o procEventLog procEventLog.cpp  -lboost_date_time

procWeatherGov: procWeatherGov.cpp weather_gov.h
	g++ -o procWeatherGov procWeatherGov.cpp -lboost_date_time

procFurnace: procFurnace.cpp weather_gov.h
	g++ -o procFurnace procFurnace.cpp

