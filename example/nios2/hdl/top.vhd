-- Top level for the minimal Nios II example: a clock and an active-low reset
-- into the generated Platform Designer system, nothing else.
library ieee;
use ieee.std_logic_1164.all;

entity top is
    port (
        clk   : in std_logic;
        rst_n : in std_logic
    );
end entity top;

architecture rtl of top is

    -- Platform Designer emits Verilog; the component is declared here so the
    -- VHDL side has a matching interface.
    component nios_min is
        port (
            clk_clk       : in std_logic;
            reset_reset_n : in std_logic
        );
    end component nios_min;

begin

    u_sys : nios_min
        port map (
            clk_clk       => clk,
            reset_reset_n => rst_n
        );

end architecture rtl;
