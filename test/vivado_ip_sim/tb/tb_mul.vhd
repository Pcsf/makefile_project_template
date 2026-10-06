-- Measures the multiplier's latency in clocks: 0 from the stub, the configured
-- pipeline depth from the vendor's simulation model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mul is
end entity;

architecture sim of tb_mul is
  signal clk  : std_logic := '0';
  signal done : boolean   := false;
  signal a, b : std_logic_vector(7 downto 0) := (others => '0');
  signal p    : std_logic_vector(15 downto 0);
begin
  clk <= not clk after 5 ns when not done else '0';

  u_dut : entity work.mul8
    port map (CLK => clk, A => a, B => b, P => p);

  process
    variable n : natural := 0;
  begin
    for i in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    a <= std_logic_vector(to_unsigned(3, 8));
    b <= std_logic_vector(to_unsigned(5, 8));
    wait for 1 ns;
    while unsigned(p) /= 15 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      n := n + 1;
      assert n < 20 report "product never arrived" severity failure;
    end loop;
    report "LATENCY=" & integer'image(n);
    report "CASE PASS";
    done <= true;
    wait;
  end process;
end architecture;
