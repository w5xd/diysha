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
static const size_t BUFSIZE = 1024;
static void GetMessages(w5xdInsteon::PlmMonitorIO& modem, std::vector<std::string>& results);
static void ProcessMessages(const std::vector<std::string>& results, bool printUnprocessed);
static void DeleteFromGateway(w5xdInsteon::PlmMonitorIO& modem, unsigned oldestMessageId);
static void RunTest(bool printUnprocessed);
static std::string readResponse(w5xdInsteon::PlmMonitorIO& modem)
{
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
    return response;
}

int main(int argc, char* argv[])
{
    unsigned oldestToDelete(0);
    bool doDelete(false);
    bool doGet(false);
    bool printUnprocessed(false);
    int sendNodeId = -1;
    bool queueSend(false);
    std::string messageForNode = "test";
    if (argc > 2)
    {
        if ((strcmp("GET", argv[2]) == 0) ||
            (printUnprocessed = strcmp("GETALL", argv[2]) == 0))
        {
            if (argc == 3)
                doGet = true;
        }
        else if (strcmp("DEL", argv[2]) == 0)
        {
            if (argc == 4)
            {
                doDelete = true;
                oldestToDelete = atoi(argv[3]);
            }
        }
        else if (strcmp("SENDTEST", argv[2]) == 0)
        {
            sendNodeId = 254;
            if (argc > 3)
                sendNodeId = atoi(argv[3]);
        }
        else if (strcmp("SEND", argv[2]) == 0 ||
            (queueSend = strcmp("FORWARD", argv[2]) == 0))
        {
            if (argc < 4)
                std::cerr << "SEND/FORWARD requires node id" << std::endl;
            else {
                sendNodeId = atoi(argv[3]);
                messageForNode = "";
                for (int i = 4; i < argc; i++)
                {
                    messageForNode += argv[i];
                    messageForNode += " ";
                }
            }
        }
    }
    if (!doGet && !doDelete && sendNodeId <= 0)
    {
        std::cerr << "Usage: procWirelessGateway <COMPORT> GET | DEL | SEND [N] [cmd] | FORWARD [N] [cmd] | SENDTEST <N>" << std::endl;
        return 1;
    }
    std::string comport;
    comport = argv[1];

    if (comport == "TEST_MESSAGES")
    {
        RunTest(printUnprocessed);
        return 0;
    }

    w5xdInsteon::PlmMonitorIO modem(comport.c_str(), 9600);
    int r = modem.OpenCommPort();
    if (r != 0)
    {
        std::cerr << "Failed to open COM port " << comport << " result: " << r << std::endl;
        return 1;
    }


    if (doGet)
    {
        std::vector<std::string> results;
        GetMessages(modem, results);
        ProcessMessages(results, printUnprocessed);
    }
    else if (doDelete)
        DeleteFromGateway(modem, oldestToDelete);
    else if (sendNodeId > 0)
    {
        std::ostringstream oss;
        if (queueSend)
            oss << "ForwardMessageToNode ";
        else
            oss << "SendMessageToNode ";
        oss << sendNodeId << " " << messageForNode << "\r";
        modem.Write((const unsigned char*)oss.str().c_str(), oss.str().length());
        auto response = readResponse(modem);
        std::cout << response;
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

static float CtoF(float c) { return 32.f + c * 9.0f / 5.0f; }

/* The main thing we do in this executable that cannot be easily done elsewhere is attach local time timestamp
*  to the messages read from the gateway.
*  Doing the unit conversion was a design mistake, but degrees F are written into old log files that, in turn,
*  are displayed on graphs, so that mistake cannot be corrected until/unless the work to deal with those
*  old files is done.
*/
static void GetMessages(w5xdInsteon::PlmMonitorIO& modem, std::vector<std::string>& results)
{
    // send the command to the WirelessGateway
    static const char GETMESSAGES[] = "GetMessages\r";
    modem.Write((unsigned char*)GETMESSAGES, sizeof(GETMESSAGES) - 1);

    // read its answers until we go a time with no answer
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

}

static void ProcessMessages(const std::vector<std::string> &results, bool printUnprocessed)
{

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
        NODETEMPERATURE1, NODETEMPERATURE2, NODE_RH1, NODE_RH2, NODE_RH3,
        PARSE_SUCCESS,
        HVACNODE1, HVACNODE2,
    };

    // for every line in the gateway response..
    for (auto& line : results)
    {
        // looking for WirelessThermometer reports in the gateway.
        // They are of this form:
        //Queue 33 5299 REC -59 3 C:44, B:263, T:+20.31
        // ...or...
        //Queue 44 3 REC -28 6 C:0, B:273, T:+26.18 R:58.27
        //
        //PacketRaingauge messages look like:
        //Queue 45 3 REC -59 21 C:1, B:273, T:+26.18, RG:1, F:2100 
        // RG:1 means 1mm of rain since last report. 
        // C, B and T are like PacketThermometer

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
        std::string rainGauge;

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
            static const char RainGaugeText[] = "RG:";

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
                }
                else if (parseForUnsigned(c, rssi, counter, error))
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
                        Ti = static_cast<float>(atof(q + 3));
                        q = strstr(line.c_str(), "To:");
                        if (q)
                        {
                            To = static_cast<float>(atof(q + 3));
                            q = strstr(line.c_str(), "Ts:");
                            if (q)
                            {
                                q += 3;
                                Ts = static_cast<float>(atof(q));
                                while (*q && !isspace(*q))
                                    q += 1;
                                hvacreport = q;
                            }
                        }
                    }
                    state = HVACNODE1;
                }
                else if (error && (error = false, parseForString(c, HviText, sizeof(HviText), counter, error)))
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
                    }
                    else
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
                    }
                    else
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
                if (!tempCstr.empty())
                {
                    if (tempCstr[0] == ' ')
                        tempCstr = tempCstr.substr(1);
                    else if (!(tempCstr[0] == '-' || tempCstr[0] == '+' ))
                        break;
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
                else if (c == ',')
                {
                    std::string temp = line.substr(lineIdx + 1);
                    while (!temp.empty() && isspace(*temp.begin()))
                        temp.erase(temp.begin());
                    if (temp.find(RainGaugeText) != temp.npos)
                    {
                        rainGauge = temp;
                        state = PARSE_SUCCESS;
                    }
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

            if (static_cast<int>(state) < static_cast<int>(HVACNODE1))
            {
                oss << nodeId << " " << buf << " " << std::fixed << std::setw(6) << std::setprecision(2) <<
                    CtoF(tempC) << // present as farenheit
                    " " <<
                    nodeBattery << " " <<
                    rssiVal << " " <<
                    nodeCount;
                if (humidityPercent > 0.f)
                    oss << " " << humidityPercent;
                if (!rainGauge.empty())
                    oss << " " << rainGauge;
            }
            else if (state == HVACNODE2)
            {
                oss << nodeId << " " << buf << " " << rssiVal << " HVAC " << hvacreport;
            }
            else if (state == HVACNODE1)
            {
                if (Ti != 0 || To != 0 || Ts != 0)
                    oss << nodeId << " " << buf << " " << rssiVal << " HVAC Ti:" << CtoF(Ti) <<
                    " To:" << CtoF(To) <<
                    " Ts:" << CtoF(Ts) << " " << hvacreport;
            }
            if (!oss.str().empty())
                std::cout << oss.str() << std::endl;
        }
        else if (printUnprocessed)
            std::cout << line << std::endl;
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
    std::string response = readResponse(modem);
    if (!response.empty())
        std::cerr << "Modem" << response << std::endl;
}


void RunTest(bool printUnprocessed)
{
    std::vector<std::string> results;
    results.push_back("QueueBegin");
    results.push_back("Queue 53 148 REC -69 99 Ti:56.5 To:56.5 Ts:-28.8 2021-11-17T22:23:36");
    results.push_back("Queue 54 35 REC -70 99 Ti:56.5 To:56.5 Ts:-28.8 2021-11-17T22:25:29");
    results.push_back("Queue 55 5 REC -70 99 HVi=--------- HVo=--------- 2021-11-17T22:25:29");
    results.push_back("Queue 56 5299 REC -59 3 C:44, B:263, T:+20.31");
    results.push_back("Queue 57 5287 REC -28 4 C:22, B:282, T:+21.18");
    results.push_back("Queue 58 5027 REC -59 3 C:45, B:264, T:+20.37");
    results.push_back("Queue 59 4916 REC -28 4 C:23, B:282, T:+21.18");
    results.push_back("Queue 60 4755 REC -58 3 C:46, B:264, T:+20.56");
    results.push_back("Queue 61 3 REC -28 6 C:0, B:273, T:+26.18 R:58.27");
    results.push_back("Queue 62 5028 REC -59 3 C:45, B:264, T:<20.37");
    results.push_back("Queue 63 5029 REC -59 3 C:45, B:264, T: 00.0");
    results.push_back("QueueEnd");
    results.push_back("QueueBytesFree 9");
    ProcessMessages(results, printUnprocessed);

}