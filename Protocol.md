

Client sends commands:

* Keyboard
    * $00 _size=1_ _keystate_      >=128 indicates a key is down, else no key down
* Buttons/Apple Keys
    * $10 _size=1_ _BUTN0_         >=128 indicates button0 is down, else button0 up
    * $11 _size=1_ _BUTN0_         >=128 indicates button1 is down, else button1 up
* Paddles/Joystick
    * $20 _size=1_ _PDL0_          Paddle 0/Joystick X-axis state, 0...255
    * $21 _size=1_ _PDL1_          Paddle 1/Joystick Y-axis state, 0...255
* Mouse - _TBD_
    * $30 _size=2_ _MOUSEXLO_ _MOUSEXHI_ mouse x pos 0...65535
    * $31 _size=2_ _MOUSEYLO_ _MOUSEYHI_ mouse x pos 0...65535
    * $32 _size=1_ _MOUSEBTN_      mouse button state
* Screen
    * $80 _size=0_                 please send screen; client waits for 8192 byte buffer


Switch mouse to be signed 8-bit deltax, deltay ?
