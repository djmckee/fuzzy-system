 #include <Timer.h>
 #include "BlinkToRadio.h"

configuration BlinkToRadioAppC {}

implementation {
  components BlinkToRadioC;

  components MainC;
  components LedsC;
  components AMSendReceiveC as Radio;
  components new TimerMilliC() as Timer0;

  /**
   * The acknowledgement message timeout timer, to ensure that acknowledgement
   * messages have been received succesfully or if they haven't, to retry the
   * sending of the current to-be-delivered message.
   */
  components new TimerMilliC() as AckMsgTimer;

  BlinkToRadioC.Boot -> MainC;
  BlinkToRadioC.RadioControl -> Radio;

  BlinkToRadioC.Leds -> LedsC;
  BlinkToRadioC.Timer0 -> Timer0;
  BlinkToRadioC.AckMsgTimer -> AckMsgTimer;

  BlinkToRadioC.Packet -> Radio;
  BlinkToRadioC.AMPacket -> Radio;
  BlinkToRadioC.AMSendReceiveI -> Radio;
}
