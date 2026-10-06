-- Behavioural stand-in for the mult_gen instance mul8: same ports, no
-- pipeline. Latency 0 is what tells the testbench it is running the stub.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mul8 is
  port (
    CLK : in  std_logic;
    A   : in  std_logic_vector(7 downto 0);
    B   : in  std_logic_vector(7 downto 0);
    P   : out std_logic_vector(15 downto 0)
  );
end entity;

architecture sim of mul8 is
begin
  P <= std_logic_vector(unsigned(A) * unsigned(B));
end architecture;
