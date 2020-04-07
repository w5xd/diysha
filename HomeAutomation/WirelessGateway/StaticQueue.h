#pragma once
#ifndef STATIC_QUEUE_BYTE_LENGTH
#define STATIC_QUEUE_BYTE_LENGTH 1024 // on a UNO, this is half available RAM
#endif

/*
* Some classes to manage a static queue.
*
* The compile time symbol STATIC_QUEUE_BYTE_LENGTH is the compile-time size,
* in bytes, of the queue memory. Each element in the queue gets
* A string of bytes, up to 255 characters long
* A status byte with these bits: ISTX, WAITING, ACKEDOK
* A message id, counted from setup starting with zero and overflowing at 255
* A node id in the rage 0 through 255
* An unsigned short for RSSI (radio signal strength)
*
* The queue is FIFO only.
*/

namespace StaticQueue
{
    const size_t QUEUE_BYTE_LENGTH = STATIC_QUEUE_BYTE_LENGTH;

    unsigned char QueueContents[QUEUE_BYTE_LENGTH]; // memory holding the queue
    unsigned short IndexOfFirstEntry; // in bytes
    unsigned short IndexBeyondLastEntry;	// in bytes
    unsigned char MessageIdCounter;	// repeats every 256 push's

    /*
    * QueueEntry is the interface to a single entry in the queue
    */
    class QueueEntry {
    public:
        // Constructed with an offset into QueueContents
        QueueEntry(short idxInQueueContents)
            : m_idx(idxInQueueContents)
        {}

        QueueEntry &operator = (const QueueEntry &other)
        {
            m_idx = other.m_idx;
            return *this;
        }

        unsigned char MessageLength() const { return QueueContents[modIdx(m_idx + MESSAGE_LEN_IDX)]; }
        unsigned char NodeId() const { return QueueContents[modIdx(m_idx + NODEID_IDX)]; }
        unsigned char MessageId() const {return QueueContents[modIdx(m_idx + MESSAGE_ID_IDX)]; }

#if !defined(STATIC_QUEUE_OMIT_SERIAL)
        void SerialPrint() const
        {
            unsigned char len = MessageLength();
            unsigned short idx = m_idx + QUEUE_ENTRY_LENGTH;
            while (len-- != 0)
            {
                Serial.print((char)(QueueContents[idx++]));
                idx = modIdx(idx);
            }
        }
#endif

        // copy the Message out of the queue. handle the wrap around
        // the end of QueueContents
        unsigned char CopyMessage(unsigned char *pBuf, unsigned char max) const
        {
            unsigned char ret = 0;
            unsigned char len = MessageLength();
            unsigned short idx = m_idx + QUEUE_ENTRY_LENGTH;
            while ((len-- != 0) && (max-- != 0))
            {
                idx = modIdx(idx);
                *pBuf++ = QueueContents[idx++];
                ret += 1;
            }
            return ret;
        }

        bool AmLast() const {  return next() == IndexBeyondLastEntry; }

        short getRSSI() const
        {
            short ret = QueueContents[modIdx(m_idx + RSS_HIGH_IDX)];
            ret <<= 8;
            ret |= QueueContents[modIdx(m_idx + RSS_LOW_IDX)];
            return ret;
        }

        void setRSSI(short r)
        {
            QueueContents[modIdx(m_idx + RSS_HIGH_IDX)] = (unsigned char)(r >> 8);
            QueueContents[modIdx(m_idx + RSS_LOW_IDX)] = (unsigned char)r;
        }

        unsigned short getTime() const
        {
            unsigned short ret = QueueContents[modIdx(m_idx + TIME_HIGH_IDX)];
            ret <<= 8;
            ret |= QueueContents[modIdx(m_idx + TIME_LOW_IDX)];
            return ret;
        }

        void setTime(unsigned short r)
        {
            QueueContents[modIdx(m_idx + TIME_HIGH_IDX)] = (unsigned char)(r >> 8);
            QueueContents[modIdx(m_idx + TIME_LOW_IDX)] = (unsigned char)r;
        }

        unsigned char &Status(){       return QueueContents[modIdx(m_idx + STATUS_IDX)];    }
        unsigned char Status() const{  return QueueContents[modIdx(m_idx + STATUS_IDX)];    }

        bool isTx() const { return Status() & (1 << ISTX); }
        bool isRx() const { return !isTx(); }
        bool isWaiting() const { return Status() & (1 << WAITING); }
        bool AckedOK() const { return Status() & (1 << ACKEDOK); }

        void clrWaiting() { Status() &= ~(1 << WAITING); }
        void setAckedOK() { Status() |= (1 << ACKEDOK); }

    private:
        friend class QueueManager;
        enum { MESSAGE_LEN_IDX, MESSAGE_ID_IDX, NODEID_IDX, STATUS_IDX, RSS_HIGH_IDX, RSS_LOW_IDX, TIME_HIGH_IDX, TIME_LOW_IDX,
            QUEUE_ENTRY_LENGTH};

        // field definitions
        enum BITS_IN_STATUS { ISTX, WAITING, ACKEDOK };

        //	initialization
        static unsigned char InitTxStatus()   { return 1 << ISTX | 1 << WAITING;    }
        static unsigned char InitRxStatus() { return 0; }

        // access functions
        unsigned short modIdx  (unsigned short idx)const {
            return (idx >= QUEUE_BYTE_LENGTH) ? idx - QUEUE_BYTE_LENGTH : idx;
        }

        unsigned short next() const {
            return modIdx( m_idx + QUEUE_ENTRY_LENGTH + MessageLength());
        }

        unsigned short init(unsigned char NodeId, bool isTx, unsigned char len)
        {
            QueueContents[modIdx(m_idx + NODEID_IDX)] = NodeId;
            QueueContents[modIdx(m_idx + MESSAGE_LEN_IDX)] = len;
            QueueContents[modIdx(m_idx + STATUS_IDX)] = isTx ? InitTxStatus() : InitRxStatus();
            QueueContents[modIdx(m_idx + MESSAGE_ID_IDX)] = MessageIdCounter++;
            return modIdx(m_idx + QUEUE_ENTRY_LENGTH);
        }

        // state
        short m_idx;
    };

    struct QueueManager {
        static bool empty() {
            return IndexOfFirstEntry == IndexBeyondLastEntry;
        }

        static QueueEntry first()
        {        return QueueEntry(IndexOfFirstEntry);    }

        static QueueEntry next(const QueueEntry &qe)
        {        return QueueEntry(qe.next());    }

        static unsigned short QueueBytesFree()
        {
            short inQueue = IndexBeyondLastEntry - IndexOfFirstEntry;
            if (inQueue < 0)
                inQueue += QUEUE_BYTE_LENGTH;
            // is bytes IN queue
            unsigned short leftOver = QUEUE_BYTE_LENGTH - inQueue; // convert to bytes NOT in queue
            return leftOver;
        }

        static bool isRoomFor(unsigned char MessageLength)
        {
            // greater-than is important. not greater-or-equal cuz there must be a "wasted" flag byte
            return QueueBytesFree() > (unsigned short)(MessageLength + QueueEntry::QUEUE_ENTRY_LENGTH);
        }

        static void pop()    {        IndexOfFirstEntry = first().next();    }

        static QueueEntry push(unsigned char NodeId, bool isTx, const unsigned char *content, unsigned char len)
        {
            QueueEntry qe(IndexBeyondLastEntry);
            unsigned short idx = qe.init(NodeId, isTx, len);
            while (len-- != 0)
            {
                QueueContents[idx++] = *content++;
                if (idx >= QUEUE_BYTE_LENGTH)
                    idx -= QUEUE_BYTE_LENGTH;
            }
            qe.setTime((unsigned short)(millis() / 1000));
            qe.setRSSI(0);
            IndexBeyondLastEntry = qe.next();
            return qe;
        }
    };

}
