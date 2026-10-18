// SkyPilot playable Vulkos buttons: 1 LEFT, 2 RIGHT, 7 RESTART, 8 FIRE
// Includes crash detection with red game-over screen.
// 640x480 VGA timing. Feed clk with approximately 25 MHz.
// At 25 MHz: horizontal 31.25 kHz and vertical ~59.52 Hz.
`default_nettype none
module vga_timing (
    input wire clk,
    input wire rst_n,
    input wire ena,
    output reg [9:0] x,
    output reg [9:0] y,
    output wire visible,
    output wire hsync,
    output wire vsync,
    output wire frame_tick
);
    localparam [9:0] H_TOTAL = 10'd800;
    localparam [9:0] V_TOTAL = 10'd525;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (ena) begin
            if (x == H_TOTAL - 10'd1) begin
                x <= 10'd0;
                if (y == V_TOTAL - 10'd1)
                    y <= 10'd0;
                else
                    y <= y + 10'd1;
            end else begin
                x <= x + 10'd1;
            end
        end
    end

    assign visible = (x < 10'd640) && (y < 10'd480);
    assign hsync = ~((x >= 10'd656) && (x < 10'd752));
    assign vsync = ~((y >= 10'd490) && (y < 10'd492));
    assign frame_tick = (x == 10'd799) && (y == 10'd524);
endmodule
`default_nettype wire
// Frame-paced game state, no framebuffer and no processor needed.
`default_nettype none
module sky_game (
    input wire clk,
    input wire rst_n,
    input wire ena,
    input wire frame_tick,
    input wire [7:0] steering,      // signed 2's-complement tilt, -128..127
    input wire button_mode,         // 1: steering[0] left, steering[1] right
    input wire fire,                // active-high fire button
    input wire restart,             // active-high restart button
    output reg [9:0] plane_x,
    output reg [9:0] bullet_x,
    output reg [9:0] bullet_y,
    output reg bullet_active,
    output reg [9:0] enemy_x,
    output reg [9:0] enemy_y,
    output reg [7:0] score,
    output reg game_over
);
    // External controls are asynchronous to the ASIC pixel clock. Synchronize
    // the bits before using them. For a robust external bus, latch all eight
    // inputs together in the bridge while they are stable between frames.
    reg [7:0] steering_meta, steering_sync;
    reg mode_meta, mode_sync;
    reg fire_meta, fire_sync, fire_prev;
    reg restart_meta, restart_sync;
    reg fire_pending;
    reg enemy_right;

    wire signed [7:0] tilt = $signed(steering_sync);
    wire left_cmd = mode_sync ? steering_sync[0] : (tilt < -8'sd12);
    wire right_cmd = mode_sync ? steering_sync[1] : (tilt > 8'sd12);
    wire [9:0] step_size = mode_sync ? 10'd4 :
        ((tilt > 8'sd65) || (tilt < -8'sd65) ? 10'd5 : 10'd2);

    // Coarse collision box. Check current bullet position once per frame.
    wire bullet_hit = bullet_active &&
        (bullet_x + 10'd3 >= enemy_x - 10'd14) &&
        (bullet_x <= enemy_x + 10'd14) &&
        (bullet_y <= enemy_y + 10'd11) &&
        (bullet_y + 10'd11 >= enemy_y - 10'd11);

    // The enemy is approximated by a 28x24 collision box.
    // Test both the narrow fuselage and the wider airplane wings.
    wire crash_body =
        (enemy_y + 10'd12 >= 10'd408) && (enemy_y <= 10'd451) &&
        (enemy_x + 10'd14 >= plane_x - 10'd4) &&
        (enemy_x <= plane_x + 10'd4);
    wire crash_wings =
        (enemy_y + 10'd12 >= 10'd429) && (enemy_y <= 10'd435) &&
        (enemy_x + 10'd14 >= plane_x - 10'd17) &&
        (enemy_x <= plane_x + 10'd17);
    wire plane_hit = crash_body || crash_wings;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            steering_meta <= 8'd0;
            steering_sync <= 8'd0;
            mode_meta <= 1'b0;
            mode_sync <= 1'b0;
            fire_meta <= 1'b0;
            fire_sync <= 1'b0;
            fire_prev <= 1'b0;
            restart_meta <= 1'b0;
            restart_sync <= 1'b0;
            fire_pending <= 1'b0;
            plane_x <= 10'd320;
            bullet_x <= 10'd320;
            bullet_y <= 10'd410;
            bullet_active <= 1'b0;
            enemy_x <= 10'd180;
            enemy_y <= 10'd60;
            enemy_right <= 1'b1;
            score <= 8'd0;
            game_over <= 1'b0;
        end else begin
            steering_meta <= steering;
            steering_sync <= steering_meta;
            mode_meta <= button_mode;
            mode_sync <= mode_meta;
            fire_meta <= fire;
            fire_sync <= fire_meta;
            fire_prev <= fire_sync;
            restart_meta <= restart;
            restart_sync <= restart_meta;

            // Latch short presses so they aren't missed between video frames.
            if (frame_tick)
                fire_pending <= 1'b0;
            if (fire_sync && !fire_prev)
                fire_pending <= 1'b1;

            if (ena && frame_tick) begin
                if (restart_sync) begin
                    plane_x <= 10'd320;
                    bullet_active <= 1'b0;
                    enemy_x <= 10'd180;
                    enemy_y <= 10'd60;
                    enemy_right <= 1'b1;
                    score <= 8'd0;
                    game_over <= 1'b0;
                    fire_pending <= 1'b0;
                end else if (game_over) begin
                    // Freeze the game until RESTART is pressed.
                    bullet_active <= 1'b0;
                end else if (plane_hit) begin
                    // Airplane touched an enemy: show the crash screen.
                    game_over <= 1'b1;
                    bullet_active <= 1'b0;
                end else begin
                    // Plane stays safely within left/right screen boundaries.
                    if (left_cmd && !right_cmd) begin
                        if (plane_x > 10'd20 + step_size)
                            plane_x <= plane_x - step_size;
                        else
                            plane_x <= 10'd20;
                    end else if (right_cmd && !left_cmd) begin
                        if (plane_x < 10'd620 - step_size)
                            plane_x <= plane_x + step_size;
                        else
                            plane_x <= 10'd620;
                    end

                    // Enemy moves horizontally and descends two pixels/frame.
                    if (enemy_right) begin
                        if (enemy_x >= 10'd598)
                            enemy_right <= 1'b0;
                        else
                            enemy_x <= enemy_x + 10'd2;
                    end else begin
                        if (enemy_x <= 10'd42)
                            enemy_right <= 1'b1;
                        else
                            enemy_x <= enemy_x - 10'd2;
                    end

                    if (bullet_hit) begin
                        score <= score + 8'd1;
                        bullet_active <= 1'b0;
                        enemy_y <= 10'd60;
                    end else begin
                        if (enemy_y >= 10'd470)
                            enemy_y <= 10'd60;
                        else
                            enemy_y <= enemy_y + 10'd2;

                        if (bullet_active) begin
                            if (bullet_y < 10'd12)
                                bullet_active <= 1'b0;
                            else
                                bullet_y <= bullet_y - 10'd10;
                        end else if (fire_pending || (fire_sync && !fire_prev)) begin
                            bullet_active <= 1'b1;
                            bullet_x <= plane_x;
                            bullet_y <= 10'd407;
                        end
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
// No video RAM: small sprites drawn by comparing pixel X/Y coordinates.
`default_nettype none
module sky_renderer (
    input wire [9:0] x,
    input wire [9:0] y,
    input wire visible,
    input wire [9:0] plane_x,
    input wire [9:0] bullet_x,
    input wire [9:0] bullet_y,
    input wire bullet_active,
    input wire [9:0] enemy_x,
    input wire [9:0] enemy_y,
    input wire [7:0] score,
    input wire game_over,
    output reg [1:0] red,
    output reg [1:0] green,
    output reg [1:0] blue
);
    wire player_body = (x >= plane_x - 10'd4) &&
                       (x <= plane_x + 10'd4) &&
                       (y >= 10'd408) && (y <= 10'd451);
    wire player_wings = (x >= plane_x - 10'd17) &&
                        (x <= plane_x + 10'd17) &&
                        (y >= 10'd429) && (y <= 10'd435);
    wire player_tail = (x >= plane_x - 10'd10) &&
                       (x <= plane_x + 10'd10) &&
                       (y >= 10'd445) && (y <= 10'd449);
    wire plane_pixel = player_body || player_wings || player_tail;
    wire windshield = (x >= plane_x - 10'd2) &&
                      (x <= plane_x + 10'd2) &&
                      (y >= 10'd421) && (y <= 10'd430);

    wire enemy_body = (x >= enemy_x - 10'd5) &&
                      (x <= enemy_x + 10'd5) &&
                      (y >= enemy_y - 10'd12) &&
                      (y <= enemy_y + 10'd12);
    wire enemy_wings = (x >= enemy_x - 10'd14) &&
                       (x <= enemy_x + 10'd14) &&
                       (y >= enemy_y - 10'd4) &&
                       (y <= enemy_y + 10'd4);
    wire enemy_pixel = enemy_body || enemy_wings;
    wire bullet_pixel = bullet_active &&
                        (x >= bullet_x - 10'd2) &&
                        (x <= bullet_x + 10'd2) &&
                        (y >= bullet_y) && (y <= bullet_y + 10'd10);

    // Eight binary score lamps: bit 0 on left, bit 7 on right.
    wire [9:0] hud_offset = x - 10'd14;
    wire [2:0] hud_bit = hud_offset[6:4];
    wire hud_box = (x >= 10'd14) && (x < 10'd142) &&
                   (y >= 10'd17) && (y < 10'd31) &&
                   (hud_offset[3:0] < 4'd11);

    always @* begin
        // Pale blue sky, two bits each of R, G, B.
        // An unmistakable red crash screen when the plane is hit.
        red   = game_over ? 2'b11 : 2'b01;
        green = game_over ? 2'b00 : 2'b10;
        blue  = game_over ? 2'b00 : 2'b11;
        if (!visible) begin
            red = 2'b00;
            green = 2'b00;
            blue = 2'b00;
        end else if (bullet_pixel) begin
            red = 2'b11;
            green = 2'b11;
            blue = 2'b00;
        end else if (windshield) begin
            red = 2'b11;
            green = 2'b11;
            blue = 2'b11;
        end else if (plane_pixel) begin
            red = 2'b00;
            green = 2'b01;
            blue = 2'b11;
        end else if (enemy_pixel) begin
            red = 2'b11;
            green = 2'b00;
            blue = 2'b01;
        end else if (hud_box && score[hud_bit]) begin
            red = 2'b00;
            green = 2'b11;
            blue = 2'b00;
        end else if (hud_box) begin
            red = 2'b01;
            green = 2'b01;
            blue = 2'b01;
        end else if ((y >= 10'd80 && y < 10'd84 && x >= 10'd80 && x < 10'd155) ||
                     (y >= 10'd160 && y < 10'd164 && x >= 10'd400 && x < 10'd485)) begin
            red = 2'b11;
            green = 2'b11;
            blue = 2'b11;
        end
    end
endmodule
`default_nettype wire
// SkyPilot: Tiny Tapeout-compatible VGA airplane shooter.
// Requires a ~25 MHz clock, Tiny VGA Pmod, and stable 3.3V digital inputs.
// Change module name to a UNIQUE tt_um_<your_id> before actual submission.
`default_nettype none
module tt_um_z10565_skypilot (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire [9:0] x, y;
    wire visible, hsync, vsync, frame_tick;
    wire [9:0] plane_x, bullet_x, bullet_y, enemy_x, enemy_y;
    wire bullet_active, game_over;
    wire [7:0] score;
    wire [1:0] red, green, blue;

    // VULKOS PLAYABLE MODE:
    // 1: eight visible ui_in switches act as simple game buttons.
    // 0: original wired phone mode, using uio_in[0]=fire, [1]=restart,
    //    [2]=button-mode selector and full 8-bit ui_in signed steering.
    // Change to 0 before integrating the real phone controller.
    localparam VULKOS_BUTTON_MODE = 1'b1;
    wire mode_ctrl = VULKOS_BUTTON_MODE ? 1'b1 : uio_in[2];
    wire fire_ctrl = VULKOS_BUTTON_MODE ? ui_in[7] : uio_in[0];
    wire restart_ctrl = VULKOS_BUTTON_MODE ? ui_in[6] : uio_in[1];

    vga_timing video (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .x(x), .y(y), .visible(visible),
        .hsync(hsync), .vsync(vsync), .frame_tick(frame_tick)
    );

    sky_game game (
        .clk(clk), .rst_n(rst_n), .ena(ena), .frame_tick(frame_tick),
        .steering(ui_in),
        .button_mode(mode_ctrl),
        .fire(fire_ctrl),
        .restart(restart_ctrl),
        .plane_x(plane_x),
        .bullet_x(bullet_x), .bullet_y(bullet_y),
        .bullet_active(bullet_active),
        .enemy_x(enemy_x), .enemy_y(enemy_y),
        .score(score), .game_over(game_over)
    );

    sky_renderer render (
        .x(x), .y(y), .visible(visible), .plane_x(plane_x),
        .bullet_x(bullet_x), .bullet_y(bullet_y),
        .bullet_active(bullet_active),
        .enemy_x(enemy_x), .enemy_y(enemy_y), .score(score),
        .game_over(game_over), .red(red), .green(green), .blue(blue)
    );

    // Official Tiny VGA Pmod pinout:
    // uo[0] R1, [1] G1, [2] B1, [3] VSYNC,
    // uo[4] R0, [5] G0, [6] B0, [7] HSYNC.
    assign uo_out = {hsync, blue[0], green[0], red[0],
                     vsync, blue[1], green[1], red[1]};

    // We use the 8 bidirectional I/O pins as *inputs only*.
    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

    wire _unused = &{uio_in[7:3], 1'b0};
endmodule
`default_nettype wire
