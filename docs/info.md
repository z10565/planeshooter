## PlaneShooter (Tiny Tapeout VGA Airplane Game)

## How it works
PlaneShooter is a digital arcade game written in Verilog. It generates a 640x480 VGA
video stream at a nominal 25 MHz pixel clock (approximately 59.52 Hz frame rate).
A horizontal and vertical counter produce VGA synchronization timing. The game engine
stores player, enemy, and bullet positions in registers and updates them once per
frame. A combinational pixel renderer draws the airplane, enemy, bullet, background,
and binary score without a framebuffer or processor.
A player can move the blue airplane left and right, shoot a yellow bullet at the red
enemy, and score when a bullet hits it. An airplane collision triggers a red
Game Over background. Restart clears the game and score.
The currently committed design uses VULKOS_BUTTON_MODE = 1 in Verilog: dedicated
ui_in bits are interpreted as button controls. A future wired-phone revision will
use an RP2040 bridge to translate smartphone accelerometer values into an 8-bit
signed steering bus, but the bridge and phone application are not yet verified.

## How to test
Set the chip clock to approximately 25 MHz, enable the design (ena = 1), and
hold rst_n = 0 for a few rising clock edges. Release reset with rst_n = 1.
Connect the eight dedicated uo_out signals to a Tiny VGA Pmod and connect the
adapter to a VGA-capable monitor (or simulate VGA in a compatible simulator).
With VULKOS_BUTTON_MODE = 1, the input controls are:
- ui_in[0] = 1: move left (visible Vulkos switch 1).
- ui_in[1] = 1: move right (visible Vulkos switch 2).
- ui_in[6] = 1: restart game (visible Vulkos switch 7).
- Pulse ui_in[7] from 0 to 1 and back to 0: shoot (visible Vulkos switch 8).
The game generates blue background and plane, red enemies, and yellow bullets.
A bullet-enemy collision increases the score and respawns the enemy; an enemy-plane
collision freezes the game and turns the background red. Press restart to recover.
The chip's video output follows Tiny VGA Pmod mappings on uo_out[7:0]:
red bits 1 and 0 (uo_out[0], uo_out[4]), green (uo_out[1], uo_out[5]),
blue (uo_out[2], uo_out[6]), VSYNC (uo_out[3]), HSYNC (uo_out[7]).

## External hardware
For real VGA display, use a compatible Tiny Tapeout demonstration board, a
Tiny VGA Pmod (resistor DAC and VGA socket), a VGA cable, and a VGA-input monitor.
A separately fabricated compatible ASIC or an FPGA prototype is required: an
already manufactured TT05 chip cannot be reprogrammed to run PlaneShooter.
For the current input mode, 3.3 V-compatible buttons or controller GPIO are needed.
For future smartphone tilt control, an appropriate wired USB controller/bridge
and a phone application must be developed and validated; no Wi-Fi is required.
