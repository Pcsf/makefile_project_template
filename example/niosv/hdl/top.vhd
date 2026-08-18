-- Minimal Nios V/m example.
--
-- The reset is generated on-chip so the design needs no reset pin and no
-- assumption about a board's reset polarity. The system's reset input is
-- active high: altera_reset_bridge with SYNCHRONOUS_EDGES none exports
-- reset_reset, not reset_reset_n.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
    port (
        clk : in std_logic
    );
end entity top;

architecture rtl of top is

    -- Platform Designer emits Verilog; the component is declared here so the
    -- VHDL side has a matching interface.
    component niosv_min is
        port (
            clk_clk     : in std_logic;
            reset_reset : in std_logic
        );
    end component niosv_min;

    -- Registers power up to their declared value at configuration, so this
    -- releases reset a fixed number of clocks after the device starts.
    signal por : std_logic_vector(15 downto 0) := (others => '0');

begin

    reset_release : process (clk)
    begin
        if rising_edge(clk) then
            if por(15) = '0' then
                por <= por(14 downto 0) & '1';
            end if;
        end if;
    end process reset_release;

    u_sys : niosv_min
        port map (
            clk_clk     => clk,
            reset_reset => not por(15)
        );

end architecture rtl;
