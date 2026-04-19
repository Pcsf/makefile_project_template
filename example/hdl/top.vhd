-- =============================================================================
-- top.vhd — Example top-level VHDL entity
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity top is
    generic (
        CLK_HZ   : natural := 100_000_000;
        BLINK_HZ : natural := 1
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;
        led   : out std_logic
    );
end entity top;

architecture rtl of top is

    component counter is
        generic (MAX_COUNT : natural);
        port (
            clk   : in  std_logic;
            rst_n : in  std_logic;
            tick  : out std_logic
        );
    end component;

    signal blink_tick : std_logic;
    signal led_r      : std_logic := '0';

begin

    u_counter : counter
        generic map (MAX_COUNT => CLK_HZ / BLINK_HZ)
        port map (
            clk   => clk,
            rst_n => rst_n,
            tick  => blink_tick
        );

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            led_r <= '0';
        elsif rising_edge(clk) then
            if blink_tick = '1' then
                led_r <= not led_r;
            end if;
        end if;
    end process;

    led <= led_r;

end architecture rtl;
