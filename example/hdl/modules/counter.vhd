-- =============================================================================
-- counter.vhd — Generic countdown/tick generator
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    generic (
        MAX_COUNT : natural := 100_000_000
    );
    port (
        clk   : in  std_logic;
        rst_n : in  std_logic;
        tick  : out std_logic
    );
end entity counter;

architecture rtl of counter is

    signal cnt : natural range 0 to MAX_COUNT - 1 := 0;

begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            cnt  <= 0;
            tick <= '0';
        elsif rising_edge(clk) then
            if cnt = MAX_COUNT - 1 then
                cnt  <= 0;
                tick <= '1';
            else
                cnt  <= cnt + 1;
                tick <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
