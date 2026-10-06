-- Never finishes: the clock runs forever and the pass marker is never reached.
-- Only a simulated-time limit ends it.
entity tb_hang is
end entity;

architecture sim of tb_hang is
  signal clk : bit := '0';
begin
  clk <= not clk after 5 ns;
  process
  begin
    wait until false;
    report "CASE PASS";
    wait;
  end process;
end architecture;
