#include <Timer.h>
#include "BlinkToRadio.h"

/**
 * The acknowledgement message timeout, in milliseconds. The acknowledgement
 * message must be recieved within this time, otherwise the message gets
 * re-sent.
 *
 * Defined here because the coursework brief said we could not modify any other
 * files, but in real life, this value would ideally be defined as a constant in
 * the BlinkToRadio.h file.
 */
#define ACK_MSG_TIMEOUT_MILLISECONDS 2000

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

  /**
   * The initial buffer for the acknowledgement message.
   */
  message_t ackMsgBuf;

  /**
   * A pointer to the acknowledgement message being sent.
   */
  message_t* ackMsg = &ackMsgBuf; // initially points to ackMsgBuf

  /**
   * A placeholder to hold the value of the current message being sent, in-case
   * it is not delivered first time and the sending must be retried.
   */
  message_t currentMsg;

  /**
   * Determines the sequence number of the next message being sent.
   *
   * If true, the next message being sent will have a sequence number of 1, if
   * false, the next message's sequence number will be 0.
   *
   * This boolean then gets inverted, to toggle the sequence number of the next
   * message to be sent, in the Timer0.fired() implementation.
   *
   * Initialised to false so that the first message has a sequence number of 0.
   */
  bool positiveSequence = FALSE;

  /**
   * A flag to state whether or not the acknoweldgement message for the current
   * message being sent has been recieved.
   *
   * Set to false when a message is about to be sent, and true when the
   * acknowledgement for the message has been received.
   *
   * Initialsed to false to fail-safe, rather than fail-deadly.
   */
  bool ackReceived = FALSE;

  /**
   * A flag to indicate whether or not it is the first message send within this
   * program's run. Set to true initially, and then set to false when the first
   * message send occurs, in the Timer0.fired() implementation.
   */
  bool isFirstSend = TRUE;

  /**
   * The acknowledgement message checking timer timeout, in milliseconds.
   *
   * Set to a constant value, which ideally would be defined in BlinkToRadio.h.
   */
  uint16_t ackMsgTimeout = ACK_MSG_TIMEOUT_MILLISECONDS;

  event void Boot.booted() {
    call RadioControl.start();
  };

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      call Timer0.startPeriodic(TIMER_PERIOD_MILLI);
    }
  };

  event void RadioControl.stopDone(error_t error){ };

  event void Timer0.fired() {
    BlinkToRadioMsg* btrpkt;

    // Only send if this is the first run, or, if an ack has been received...
    if (isFirstSend || ackReceived) {
      // No longer the first send...
      if (isFirstSend) {
        isFirstSend = FALSE;
      }

      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);
      call Packet.setPayloadLength(sendMsg, sizeof(BlinkToRadioMsg));

      btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, sizeof (BlinkToRadioMsg)));

      // We're sending data - not an acknowledgement.
      btrpkt->type = TYPE_DATA;

      // Work out sequence number so that it's the inverse of last packet send.
      if (positiveSequence) {
        // Sequence number is positive (i.e. 1)
        btrpkt->seq = 1;

      } else {
        // Sequence number is not positive (i.e. 0)
        btrpkt->seq = 0;

      }

      // Flag the seqeunce number so that it is inverted on next send.
      positiveSequence = !positiveSequence;

      // Send to the desired mote that's been defined in BlinkToRadio.h
      btrpkt->nodeid = TOS_NODE_ID;

      // Increment and send the 'next' counter value
      counter++;
      btrpkt->counter = counter;

      // We need to reset the ack flag because the message we're about to send requires acknowledgement
      ackReceived = FALSE;

      // Cache current message.
      currentMsg = *sendMsg;

      // send message and store returned pointer to free buffer for next message
      sendMsg = call AMSendReceiveI.send(sendMsg);

    } else {
      // Haven't received an acknowledgment yet, start waiting for a timeout...
      // Call the timeout timer to fire once (i.e. single shot) in 2 seconds.
      // Looked up at http://www.tinyos.net/tinyos-2.1.0/doc/nesdoc/mica2/ihtml/tos.lib.timer.Timer.html
      call AckMsgTimer.startOneShot(ackMsgTimeout);

    }

  }

  /**
   * The timout timer that I implemented to ensure that acknowledge messages
   * have been received.
   */
  event void AckMsgTimer.fired() {
    // If this timer gets fired and the ack message has not been received,
    // then re-send the 'currentMsg' data...
    if (!ackReceived) {
      // Re-send 'current message' from the cached placeholder var.
      call AMSendReceiveI.send(&currentMsg);

    }

  }

  event message_t* AMSendReceiveI.receive(message_t* msg) {
    uint8_t len = call Packet.payloadLength(msg);
    BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(msg, len));

    BlinkToRadioMsg* ackpkt;

    // Does the packet recieved have a counter field value that matches the current counter value?
    // If so, and if the message is an acknowledgement, then this is the acknowledgement corresponding
    // to the message being sent, and should be flagged as such.
    bool packetCounterMatch = (btrpkt->counter == counter);

    // Is it data or an acknowledgement - check the 'type' field and act accordingly...
    if (btrpkt->type == TYPE_DATA) {
      // Data - display on LEDs...
      call Leds.set(btrpkt->counter);

      // Send acknowledgement message - we've received and utilised the data packet...
      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);
      call Packet.setPayloadLength(sendMsg, sizeof(BlinkToRadioMsg));

      // Create the acknowledgement packet, mirroring the packet sent
      ackpkt = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, sizeof (BlinkToRadioMsg)));
      
      // This is an acknowledgement message; set type as such.
      ackpkt->type = TYPE_ACK;

      // Make the rest of the fields of the ack message mirror the received data message.
      ackpkt->seq = btrpkt->seq;
      ackpkt->nodeid = btrpkt->nodeid;
      ackpkt->counter = btrpkt->counter;

      // send message and store returned pointer to free buffer for next message
      ackMsg = call AMSendReceiveI.send(sendMsg);

    } else if (btrpkt->type == TYPE_ACK && packetCounterMatch) {
      // Acknoweledgement type which matches the count of the ack we need
      // - set bool to allow sending of next packet.
      ackReceived = TRUE;

      // Stop the ack message timeout timer, if it's running...
      // Looked up the timer methods at http://www.tinyos.net/tinyos-2.1.0/doc/nesdoc/mica2/ihtml/tos.lib.timer.Timer.html
      bool timerIsRunning = call AckMsgTimer.isRunning();
      if (timerIsRunning) {
          // Timer's currently running but acknowledgement has been received,
          // so stop it because it's no longer needed.
          call AckMsgTimer.stop();

      }

    }

    return msg; // no need to make msg point to new buffer as msg is no longer needed

  }


}
