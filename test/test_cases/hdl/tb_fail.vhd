entity tb_fail is
end entity;

architecture sim of tb_fail is
begin
  process
  begin
    wait for 1 us;
    report "check failed" severity failure;
    wait;
  end process;
end architecture;
