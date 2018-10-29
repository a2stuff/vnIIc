

Client sends commands:

* Keyboard
    * $00 _keystate_      >=128 indicates a key is down, else no key down
* Buttons/Apple Keys
    * $10 _BUTN0_         >=128 indicates button0 is down, else button0 up
    * $11 _BUTN0_         >=128 indicates button1 is down, else button1 up
* Paddles/Joystick
    * $20 _PDL0_          Paddle 0/Joystick X-axis state, 0...255
    * $21 _PDL1_          Paddle 1/Joystick Y-axis state, 0...255
* Mouse - _TBD_
    * $30 _MOUSEXLO_ _MOUSEXHI_ mouse x pos 0...65535
    * $31 _MOUSEYLO_ _MOUSEYHI_ mouse x pos 0...65535
    * $32 _MOUSEBTN_      mouse button state
* Screen
    * $80                 please send screen; client waits for 8192 byte buffer
