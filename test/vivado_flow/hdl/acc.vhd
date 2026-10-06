library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity acc is
  port (
    clk : in  std_logic;
    d   : in  unsigned(7 downto 0);
    q   : out unsigned(7 downto 0)
  );
end entity;

architecture rtl of acc is
  signal r : unsigned(7 downto 0) := (others => '0');
begin
  r <= r + d when rising_edge(clk);
  q <= r;
end architecture;
