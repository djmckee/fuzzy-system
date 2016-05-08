 #include <Timer.h>
 #include "BlinkToRadio.h"

module BlinkToRadioC {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;

    interface Leds;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as AckTimoutTimer;

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
   * The timeout time in milliseconds.
   * I would make this value a compile-time constant definition in
   * BlinkToRadio.h, but we haven't been told that we can modify that
   * file in this coursework, so an implementation constant here
   * shall have to suffice.
   */
   uint16_t timeoutPeriod = 2000;

  /**
   * A placeholder variable to keep track of the current sequence number.
   */
  uint16_t sequenceNumber = 0;

  /**
   * A boolean to store whether or not the current message has been acknowledged.
   * Default to false for safety.
   */
   bool hasAcknowledgedMessage = FALSE;

   /**
    * A flag to indicate if this is the first message send. Defaults to
    * TRUE, but should be set to FALSE on first message send (attempt).
    */
   bool firstMessageFlag = TRUE;

  event void Boot.booted() {
    call RadioControl.start();
  };

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      call Timer0.startPeriodic(TIMER_PERIOD_MILLI);
    }
  };

  event void RadioControl.stopDone(error_t error){};



  event void Timer0.fired() {
    // Only send another message if the current one has been acknowledged,
    // or it is the first message...
    if (hasAcknowledgedMessage || firstMessageFlag) {
      // Ensure that it is no longer flagged as the first message...
      if (firstMessageFlag) {
        firstMessageFlag = FALSE;
      }

      BlinkToRadioMsg* btrpkt;

      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);
      call Packet.setPayloadLength(sendMsg, sizeof(BlinkToRadioMsg));

      btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, sizeof (BlinkToRadioMsg)));
      counter++;
      btrpkt->type = TYPE_DATA;
      btrpkt->seq = 0;
      btrpkt->nodeid = TOS_NODE_ID;
      btrpkt->counter = counter;

      // A message cannot be acknowledged before it is sent...
      hasAcknowledgedMessage = FALSE;

      // send message and store returned pointer to free buffer for next message
      sendMsg = call AMSendReceiveI.send(sendMsg);

      // Start timeout timer to catch message if it fails to send...
      call AckTimoutTimer.startOneShotAt(call AckTimoutTimer.getNow(), timeoutPeriod);

    }
  }



  event message_t* AMSendReceiveI.receive(message_t* msg) {
    uint8_t len = call Packet.payloadLength(msg);
    BlinkToRadioMsg* btrpkt = (BlinkToRadioMsg*)(call Packet.getPayload(msg, len));
    call Leds.set(btrpkt->counter);

    // Is the packet we recieved of an ackowledgement packet type?
    nx_uint16_t type = btrpkt->type;

    if (type == TYPE_ACK) {
      // Message acknowledged, set flag boolean so that next bit of data will get sent...
      hasAcknowledgedMessage = TRUE;

      // Stop timeout from firing and sending current message again in the meantime...
      call AckTimoutTimer.stop();

    } else if (type == TYPE_DATA) {
      // Packet is data - send ackowledgement back to sender...
      // (I used the code I wrote for Tutorial 4 to help with this acknowledgement packet...)

      // Set the packet to send to have the same properties as the message recieved...
      call AMPacket.setType(sendMsg, AM_BLINKTORADIO);
      call AMPacket.setDestination(sendMsg, DEST_ECHO);
      call AMPacket.setSource(sendMsg, TOS_NODE_ID);

      uint16_t messageLength = sizeof(BlinkToRadioMsg);

      call AMPacket.setPayloadLength(sendMsg, messageLength);

      // Instantiate a new acknowledgement message from the sendMsg
      BlinkToRadioMsg *ackMsg = (BlinkToRadioMsg*)(call Packet.getPayload(sendMsg, messageLength));

      // Set up the message with the properties of an acknowledgement to the mote we're communicating with...
      ackMsg->type = TYPE_ACK;
      ackMsg->nodeid = TOS_NODE_ID;
      ackMsg->counter = counter;

      // TODO: Sequence number mindfuck.
      /*
      // If the previous sequence number was even, make this current one odd, and ensure the next is odd...
      if (sequenceNumber == 0)  {
        // Ensure the next sequence number is odd...
        sequenceNumber = 1;
      } else {

      }

      // And set sequence number of the message to the current value
      ackMsg->seq = sequenceNumber;
      */

      // Send acknowledgement message that we've set up...
      call AMSendReceiveI.send(sendMsg);

    }

    return msg; // no need to make msg point to new buffer as msg is no longer needed
  }


  /**
   * Timer method to ensure that the positive acknowledgement is recieved -
   * if this timer is fired and an acknowledgement message has not
   * been recieved, then the current message being sent should be
   * re-sent.
   */
   event void AckTimoutTimer.fired() {
     // Check if the message has been acknowledged?
     if (!hasAcknowledgedMessage) {
       // Message not ackowledged - re-send it...
       call AMSendReceiveI.send(&sendMsg);

     }

   }

}
