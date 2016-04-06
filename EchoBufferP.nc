// $Id: BaseStationP.nc,v 1.10 2008/06/23 20:25:14 regehr Exp $

/*									tab:4
 * "Copyright (c) 2000-2005 The Regents of the University  of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 * Copyright (c) 2002-2005 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/*
 * @author Phil Buonadonna
 * @author Gilman Tolle
 * @author David Gay
 * Revision:	$Id: BaseStationP.nc,v 1.10 2008/06/23 20:25:14 regehr Exp $
 */
  
/* 
 * BaseStationP bridges packets between a serial channel and the radio.
 * Messages moving from serial to radio will be tagged with the group
 * ID compiled into the TOSBase, and messages moving from radio to
 * serial will be filtered by that same group id.
 */

/*
 * Program heavily modified to act as Echo with Buffers.
 * Almost any message arriving on the radio with destination = TOS_NODE_ID will be echoed back to the sender.
 * Every 4th message sent on ID = 99 will be dropped. 
 */

/*
 * @author Alan Tully
 */

#include "AM.h"
#include "Serial.h"

module EchoBufferP @safe() {
  uses {
    interface Boot;
    interface SplitControl as RadioControl;
    
    interface AMSend as RadioSend[am_id_t id];
    interface Receive as RadioReceive[am_id_t id];
    interface Receive as RadioSnoop[am_id_t id];
    interface Packet as RadioPacket;
    interface AMPacket as RadioAMPacket;
    interface Leds;
  }
}

implementation
{
  enum {
    RADIO_QUEUE_LEN = 12,
  };

  message_t  radioQueueBufs[RADIO_QUEUE_LEN];
  message_t  * ONE_NOK radioQueue[RADIO_QUEUE_LEN];
  uint8_t    radioIn, radioOut;
  bool       radioBusy, radioFull;

  task void radioSendTask();
  message_t* sendToRadio(message_t *msg, void *payload, uint8_t len);

  event void Boot.booted() {
    uint8_t i;

    for (i = 0; i < RADIO_QUEUE_LEN; i++)
      radioQueue[i] = &radioQueueBufs[i];
    radioIn = radioOut = 0;
    radioBusy = FALSE;
    radioFull = TRUE;

    call RadioControl.start();
  }

  event void RadioControl.startDone(error_t error) {
    if (error == SUCCESS) {
      radioFull = FALSE;
    }
  }

  event void RadioControl.stopDone(error_t error) {}

  uint8_t count = 0;

  message_t* ONE receive(message_t* ONE msg, void* payload, uint8_t len);

  event message_t *RadioSnoop.receive[am_id_t id](message_t *msg, void *payload, uint8_t len) {
    return receive(msg, payload, len);
  }
  
  event message_t *RadioReceive.receive[am_id_t id](message_t *msg, void *payload, uint8_t len) {
    return receive(msg, payload, len);
  }

  message_t* receive(message_t *msg, void *payload, uint8_t len) {
    message_t *ret = msg;  // ensure a message buffer is always returned.

    if (call RadioAMPacket.destination(msg) == TOS_NODE_ID) {
      count = (count + 1)%7;
      if ((call RadioAMPacket.type(msg) != 99) || (count!=0)) {// reject every 7th packet
        am_addr_t source = call RadioAMPacket.source(msg);
        call RadioAMPacket.setDestination(msg, source);
        call RadioAMPacket.setSource(msg, TOS_NODE_ID);
        call Leds.led1Toggle();
        ret = sendToRadio(msg, payload, len);
      }
    }
    return ret;
  }

  message_t* sendToRadio(message_t *msg, void *payload, uint8_t len) {
    message_t *ret = msg;
    bool reflectToken = FALSE;

    atomic
      if (!radioFull) {
        reflectToken = TRUE;
        ret = radioQueue[radioIn];
        radioQueue[radioIn] = msg;
        if (++radioIn >= RADIO_QUEUE_LEN)
          radioIn = 0;
        if (radioIn == radioOut)
          radioFull = TRUE;

        if (!radioBusy) {
          post radioSendTask();
          radioBusy = TRUE;
        }
      }
    return ret;
  }


  task void radioSendTask() {
    message_t* msg;
    
    atomic
      if (radioIn == radioOut && !radioFull) {
	  radioBusy = FALSE;
	  return;
      }

    msg = radioQueue[radioOut];
    
    if (call RadioSend.send[call RadioAMPacket.type(msg)](call RadioAMPacket.destination(msg), msg, call RadioPacket.payloadLength(msg)) != SUCCESS)
      post radioSendTask();
  }

  event void RadioSend.sendDone[am_id_t id](message_t* msg, error_t error) {
    if (error == SUCCESS)
      atomic
	if (msg == radioQueue[radioOut]) {
          if (++radioOut >= RADIO_QUEUE_LEN)
            radioOut = 0;
	  if (radioFull)
	    radioFull = FALSE;
	  }
    post radioSendTask();
  }
}  
