-- Passes only if it runs past 1 us. The free-running clock gives the simulator
-- events to stop on, so a shorter --stop-time ends it before the marker.
entity tb_late is
end entity;

architecture sim of tb_late is
  signal clk : bit := '0';
begin
  clk <= not clk after 5 ns;
  process
  begin
    wait for 1 us;
    report "CASE PASS";
    wait;
  end process;
end architecture;
