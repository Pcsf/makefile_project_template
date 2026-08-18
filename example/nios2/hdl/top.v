// Top level for the minimal Nios II example: a clock and an active-low reset
// into the generated Platform Designer system, nothing else.
module top (
    input wire clk,
    input wire rst_n
);

    nios_min u_sys (
        .clk_clk       (clk),
        .reset_reset_n (rst_n)
    );

endmodule
