 #include <Timer.h>
 #include "BlinkToRadio.h"

module BlinkToRadioC {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;

    interface Leds;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as AckMsgTimer;

    interface Packet;
    interface AMPacket;
    interface AMSendReceiveI;
  }
}

implementation {
  uint16_t counter = 0;
  message_t sendMsgBuf;
  message_t* sendMsg = &sendMsgBuf; // initially points to sendMsgBuf

  message_t currentMsgBuf;
  message_t* currentMsg = &currentMsgBuf; // initially points to curretMsgBuf

  message_t ackMsgBuf;
  message_t* ackMsg = &ackMsgBuf; // initially points to ackMsgBuf

  bool positiveSequence = FALSE;

  bool ackRecieved = FALSE;

  bool isFirstSend = TRUE;

  
  uint16_t ackMsgTimeout = 2000;

  event void Boot.booted() {
    call RadioControl.start();
  };

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      call Timer0.startPeriodic(TIMER_PERIOD_MILLI);
    }
  };

  event void RadioControl.stopDone(error_t error){

  };

  event void Timer0.fired() {
    BlinkToRadioMsg* btrpkt;

    // Only send if this is the first run, or, if an ack has been recieved...
    if (isFirstSend || ackRecieved) {
      // No longer the first send...
      if (isFirstSend) {
        isFirstSend = FALSE;
      }

      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);
      call Packet.setPayloadLength(sendMsg, sizeof(BlinkToRadioMsg));

      btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, sizeof (BlinkToRadioMsg)));
      counter++;
      btrpkt->type = TYPE_DATA;

      // Work out sequence number so that it's the inverse of last packet send.
      if (positiveSequence) {
        btrpkt->seq = 1;

      } else {
        btrpkt->seq = 0;

      }

      // Flag the seqeunce number so that it is inverted on next send.
      positiveSequence = !positiveSequence;

      btrpkt->nodeid = TOS_NODE_ID;
      btrpkt->counter = counter;

      // We need to reset the ack flag because the message we're about to send requires acknowledgement
      ackRecieved = FALSE;

      // Cache current message.
      currentMsg = sendMsg;

      // send message and store returned pointer to free buffer for next message
      sendMsg = call AMSendReceiveI.send(sendMsg);


    }
  }

  event void AckMsgTimer.fired() {

  }

  event message_t* AMSendReceiveI.receive(message_t* msg) {
    uint8_t len = call Packet.payloadLength(msg);
    BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(msg, len));

    BlinkToRadioMsg* ackpkt;

    bool packetCounterMatch = (btrpkt->counter == counter);

    if (btrpkt->type == TYPE_DATA) {
      // Data - display on LEDs...
      call Leds.set(btrpkt->counter);

      // Send acknowledgement message - we've recieved and utilised the data packet...
      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);
      call Packet.setPayloadLength(sendMsg, sizeof(BlinkToRadioMsg));

      ackpkt = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, sizeof (BlinkToRadioMsg)));
      // This is an acknowledgement message; set type as such.
      ackpkt->type = TYPE_ACK;

      // Make the rest of the fields of the ack message mirror the recieved data message.
      ackpkt->seq = btrpkt->seq;
      ackpkt->nodeid = btrpkt->nodeid;
      ackpkt->counter = btrpkt->nodeid;

      // send message and store returned pointer to free buffer for next message
      ackMsg = call AMSendReceiveI.send(sendMsg);

    } else if (btrpkt->type == TYPE_ACK && packetCounterMatch) {
      // Acknoweledgement - set bool to allow sending of next packet.
      ackRecieved = TRUE;

      // TODO: Stop ack timeout timer.
    }

    return msg; // no need to make msg point to new buffer as msg is no longer needed
  }

}
