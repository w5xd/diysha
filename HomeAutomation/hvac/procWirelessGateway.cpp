// procWirelessGateway.cpp : Defines the entry point for the console application.
//

#include <time.h> // old unix-style time

#if defined (WIN32)
#include <w5xdInsteon/impl/PlmMonitorWin.h>
#elif defined (LINUX32)
#include <w5xdInsteon/impl/PlmMonitorLinux.h>
#endif

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <set>
#include <chrono>
#include <thread>
#include <memory>
#include <iomanip>
#include <cstring>

/* Program to open a serial link to the WirelessGateway.
** The COM port name must be on the command line.
**
** Two modes to run:
** We send the GetMessages command to the gateway.
** Search for the stored messages from WirelessThermometer and append
** results for each nodeId. We compute a file name for each
** as specified by prefix and suffix on the command line.
**
** OR
** delete all the messages we processed from the store-and-forward
** queue in the WirelessGateway.
*/
static void GetMessages(w5xdInsteon::PlmMonitorIO& modem);
static void DeleteFromGateway(w5xdInsteon::PlmMonitorIO& modem, unsigned oldestMessageId);

int main(int argc, char* argv[])
{
    unsigned oldestToDelete(0);
    bool doDelete(false);
    bool doGet(false);
    int sendTest = -1;
    if (argc > 2)
    {
        if (strcmp("GET", argv[2]) == 0)
        {
            if (argc == 3)
                doGet = true;
        } else if (strcmp("DEL", argv[2]) == 0)
        {
            if (argc == 4)
            {
                doDelete = true;
                oldestToDelete = atoi(argv[3]);
            }
        } else if (strcmp("SENDTEST", argv[2]) == 0)
        {
            sendTest = 254;
            if (argc > 3)
                sendTest = atoi(argv[3]);
        }
    }
    if (!doGet && !doDelete && sendTest <= 0)
    {
        std::cerr << "Usage: procWirelessGateway <COMPORT> GET | DEL | SENDTEST <N>" << std::endl;
        return 1;
    }
    std::string comport;
    comport = argv[1];

    w5xdInsteon::PlmMonitorIO modem(comport.c_str(), 9600);
    int r = modem.OpenCommPort();
    if (r != 0)
    {
        std::cerr << "Failed to open COM port " << comport << " result: " << r << std::endl;
        return 1;
    }

    if (doGet)
        GetMessages(modem);
    else if (doDelete)
        DeleteFromGateway(modem, oldestToDelete);
    else if (sendTest > 0)
    {
        std::ostringstream oss;
        oss << "SendMessageToNode " << sendTest << " test\r";
        modem.Write((const unsigned char*)oss.str().c_str(), oss.str().length());
    }
    return 0;
}

// parsing function helper. search for unsigned integer in decimal, followed by space char
static bool parseForUnsigned(char c, unsigned& target, unsigned& counter, bool& error, bool ignoreSign = false)
{
    if (isdigit(c))
    {
        target *= 10;
        target += c - '0';
        counter += 1;
    } else if (ignoreSign && c == '-' && counter == 0) // ignore
        counter += 1;
    else
    {
        if (!counter || c != ' ')
            error = true;
        else
            counter = 0;
        return true;
    }
    return false;
}

// parsing function for fixed string. Search for exactly the string provided
static bool parseForString(char c, const char* Text, size_t TextSize, unsigned& counter, bool& error)
{
    if (c == Text[counter])
    {
        if (counter == TextSize - 2)
        {
            counter = 0;
            return true;
        } else
            counter++;
    } else
        error = true;
    return false;
}

static const size_t BUFSIZE = 1024;

static void GetMessages(w5xdInsteon::PlmMonitorIO& modem)
{
    // send the command to the WirelessGateway
    static const char GETMESSAGES[] = "GetMessages\r";
    modem.Write((unsigned char*)GETMESSAGES, sizeof(GETMESSAGES) - 1);

    // read its answers until we go a time with no answer
    std::vector<std::string> results;
    std::unique_ptr<unsigned char[]> buf(new unsigned char[BUFSIZE]);
    std::string partial;
    int j = 0;
    for (;;)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        unsigned w;
        if (!modem.Read(buf.get(), BUFSIZE, &w))
            break;
        if (w == 0)
            break; // timed out--didn't get anything so we're done
        j++;
        for (unsigned i = 0; i < w; i++)
        {
            char c = (char)buf[i];
            if ((c == '\r') || (c == '\n'))
            {
                if (!partial.empty())
                    results.push_back(partial);
                partial.clear();
            } else
                partial += c;
        }
    }

    /* GetMessages responds like this:
QueueBegin
Queue 53 148 REC -69 99 Ti:56.5 To:56.5 Ts:-28.8 2021-11-17T22:23:36
Queue 54 35 REC -70 99 Ti:56.5 To:56.5 Ts:-28.8 2021-11-17T22:25:29
Queue 55 5 REC -70 99 HVi=--------- HVo=--------- 2021-11-17T22:25:29
Queue 56 5299 REC -59 3 C:44, B:263, T:+20.31
Queue 57 5287 REC -28 4 C:22, B:282, T:+21.18
Queue 58 5027 REC -59 3 C:45, B:264, T:+20.37
Queue 59 4916 REC -28 4 C:23, B:282, T:+21.18
Queue 60 4755 REC -58 3 C:46, B:264, T:+20.56
Queue 61 3 REC -28 6 C:0, B:273, T:+26.18 R:58.27
QueueEnd
QueueBytesFree 9

          Gateway tag "QUEUE"
          Seconds ago it logged into the gateway
          REC eived message from network
          RSSI of received message
          NodeId received from

      Contents of message:
          Wireless Thermometer internal count
          Wireless Thermomenter battery indicator
          Temperature in C
         */

         // unix-style time formatter
    struct tm* local;
    time_t now;
    now = time(NULL);

    // track WirelessGateway message ID to delete after reading
    // (Gateway has limited memory. We have to tell it we have
    // retrieved successfully to force it delete.)
    unsigned oldestMessageId;
    bool foundEntryToDelete(false);

    enum LineParseState_t {
        QUEUE, MSGID, AGE, REC, RSSI, NODEID,
        NODECOUNT1, NODECOUNT2, NODECOUNT3,
        NODEBATTERY1, NODEBATTERY2, NODEBATTERY3,
        NODETEMPERATURE1, NODETEMPERATURE2, NODE_RH1, NODE_RH2, NODE_RH3, PARSE_SUCCESS,
        HVACNODE1, HVACNODE2
    };

    // for every line in the gateway response..
    for (auto& line : results)
    {
        // looking for WirelessThermometer reports in the gateway.
        // They are of this form:
        //Queue 33 5299 REC -59 3 C:44, B:263, T:+20.31
        // ...or...
        //Queue 44 3 REC -28 6 C:0, B:273, T:+26.18 R:58.27

        LineParseState_t state(QUEUE);
        unsigned counter(0); // count characters in the current state

        // stuff in the message we look for
        unsigned messageId(0);
        unsigned nodeId(0);
        unsigned nodeCount(0);
        unsigned nodeBattery(0);
        unsigned age(0);
        unsigned rssi(0);
        bool negRssi(false);
        float tempC(-99.f);
        float humidityPercent(-1.f);
        std::string hvacreport;
        float Ti(0), To(0), Ts(0);

        unsigned lineIdx(0); // count characters in the line
        for (auto const& c : line)
        {
            // delimiters inside a message from WirelessThermometer
            static const char QText[] = "Queue ";
            static const char RText[] = "REC ";
            static const char CText[] = "C:";
            static const char TiText[] = "Ti:";
            static const char HviText[] = "HVi=";
            static const char BText[] = "B:";
            static const char TText[] = "T:";
            static const char RhText[] = "R:";


            bool error(false);// error flag for this character. aborts line processing
            switch (state)
            {
            case QUEUE:
                if (parseForString(c, QText, sizeof(QText), counter, error))
                    state = MSGID;
                break;

            case MSGID:
                if (parseForUnsigned(c, messageId, counter, error))
                    state = AGE;
                break;

            case AGE:
                if (parseForUnsigned(c, age, counter, error))
                    state = REC;
                break;

            case REC:
                if (parseForString(c, RText, sizeof(RText), counter, error))
                    state = RSSI;
                break;

            case RSSI:
                if (counter == 0 && c == '-')
                {
                    negRssi = true;
                    counter += 1;
                } else if (parseForUnsigned(c, rssi, counter, error))
                    state = NODEID;
                break;

            case NODEID:
                if (parseForUnsigned(c, nodeId, counter, error))
                    state = NODECOUNT1;
                break;

            case NODECOUNT1:
                hvacreport.push_back(c);
                if (parseForString(c, CText, sizeof(CText), counter, error))
                    state = NODECOUNT2;
                else if (error && (error = false, parseForString(c, TiText, sizeof(TiText), counter, error)))
                {
                    const char* q = strstr(line.c_str(), "Ti:");
                    if (q)
                    {
                        Ti = atof(q + 3);
                        q = strstr(line.c_str(), "To:");
                        if (q)
                        {
                            To = atof(q + 3);
                            q = strstr(line.c_str(), "Ts:");
                            if (q)
                                Ts = atof(q + 3);
                        }
                    }
                    state = HVACNODE1;
                } else if (error && (error = false, parseForString(c, HviText, sizeof(HviText), counter, error)))
                    state = HVACNODE2;
                if (error)
                    hvacreport.clear();
                break;

            case HVACNODE2:
                hvacreport.push_back(c);
                break;
            case HVACNODE1:
                break;

            case NODECOUNT2:
                if (parseForUnsigned(c, nodeCount, counter, error, true))
                {
                    if (error && c == ',')
                    {
                        // normal successful completion
                        error = false;
                        state = NODECOUNT3;
                        counter = 0;
                    } else
                        state = NODEBATTERY1;
                }
                break;

            case NODECOUNT3:
                if (c == ' ')
                    state = NODEBATTERY1;
                else
                    error = true;
                break;

            case NODEBATTERY1:
                if (parseForString(c, BText, sizeof(BText), counter, error))
                    state = NODEBATTERY2;
                break;

            case NODEBATTERY2:
                if (parseForUnsigned(c, nodeBattery, counter, error))
                {
                    if (error && c == ',')
                    {
                        // normal trailing comma
                        error = false;
                        state = NODEBATTERY3;
                        counter = 0;
                    } else
                        state = NODETEMPERATURE1;
                }
                break;

            case NODEBATTERY3:
                if (c == ' ')
                    state = NODETEMPERATURE1;
                else
                    error = true;
                break;

            case NODETEMPERATURE1:
                if (parseForString(c, TText, sizeof(TText), counter, error))
                    state = NODETEMPERATURE2;
                break;

            case NODETEMPERATURE2:
            {
                std::string tempCstr = line.substr(lineIdx);
                if (!tempCstr.empty() && (tempCstr[0] == '-' || tempCstr[0] == '+'))
                {
                    tempC = (float)(atof(tempCstr.c_str()));
                    state = NODE_RH1;
                }
            }
            break;

            case NODE_RH1:
                if (c == ' ')
                {
                    state = NODE_RH2;
                    counter = 0;
                }
                break;

            case NODE_RH2:
                if (parseForString(c, RhText, sizeof(RhText), counter, error))
                    state = NODE_RH3;
                break;

            case NODE_RH3:
            {
                std::string humidityStr = line.substr(lineIdx);
                if (!humidityStr.empty())
                {
                    humidityPercent = (float)(atof(humidityStr.c_str()));
                    state = PARSE_SUCCESS;
                }
            }
            break;
            }
            lineIdx += 1;

            if (error)
                break;
        } // for (auto const &c : line)

        // if we parsed OK
        // Deal with success, and break the for(:line) loop 
        if (static_cast<int>(state) >= static_cast<int>(NODE_RH1))
        {
            foundEntryToDelete = true;
            oldestMessageId = messageId;
            std::ostringstream oss;

            if (static_cast<int>(state) < static_cast<int>(HVACNODE1))
            {
                time_t thisEvent = now - age; // account for time inside gateway
                local = localtime(&thisEvent);
                char buf[64];
                // old unix-style time string for first two columns in log
                sprintf(buf, "%04d/%02d/%02d %02d:%02d:%02d",
                    local->tm_year + 1900,
                    local->tm_mon + 1,
                    local->tm_mday,
                    local->tm_hour,
                    local->tm_min,
                    local->tm_sec);

                short rssiVal = negRssi ? -(short)rssi : rssi;

                oss << nodeId << " " << buf << " " << std::fixed << std::setw(6) << std::setprecision(2) <<
                    tempC / 5.f * 9.f + 32.f << // present as farenheit
                    " " <<
                    nodeBattery << " " <<
                    rssiVal << " " <<
                    nodeCount;
                if (humidityPercent > 0.f)
                    oss << " " << humidityPercent;
            } else if (state == HVACNODE2)
            {
                oss << nodeId << " HVAC " << hvacreport;
            } else if (state == HVACNODE1)
            {
                oss << nodeId << " HVAC Ti=" << 32.0 + Ti * 9.0 / 5.0 <<
                    " To=" << 32.0 + To * 9.0 / 5.0 <<
                    " Ts=" << 32.0 + Ts * 9.0 / 5.0;
            }
            std::cout << oss.str() << std::endl;
        }
    }
    if (foundEntryToDelete)
        std::cout << "Found delete: " << oldestMessageId << std::endl;
    else
        std::cout << "None found for delete" << std::endl;
    std::cout << std::flush;
}

static void DeleteFromGateway(w5xdInsteon::PlmMonitorIO& modem, unsigned oldestMessageId)
{
    // Tell WirelessGateway we processed the messages and we won't see them in a future run
    std::ostringstream msg;
    msg << "DeleteMessagesFromId " << oldestMessageId << "\r";
    modem.Write(const_cast<unsigned char*>(reinterpret_cast<const unsigned char*>(msg.str().c_str())), msg.str().length());
    // a bit for modem to respond
    std::string response;
    std::unique_ptr<unsigned char[]> buf(new unsigned char[BUFSIZE]);
    for (;;)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        unsigned w;
        if (!modem.Read(buf.get(), BUFSIZE, &w))
            break;
        if (w == 0)
            break; // timed out--didn't get anything so we're done  
        for (unsigned i = 0; i < w; i++)
            response += buf[i];
    }
    if (!response.empty())
        std::cerr << "Modem" << response << std::endl;
}
