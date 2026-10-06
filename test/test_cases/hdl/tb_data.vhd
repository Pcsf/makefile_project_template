-- Opens a file by a path relative to the project root, the way a testbench
-- reading stimulus usually does.
use std.textio.all;

entity tb_data is
end entity;

architecture sim of tb_data is
begin
  process
    file f     : text;
    variable l : line;
    variable v : integer;
    variable s : file_open_status;
  begin
    file_open(s, f, "data/value.txt", read_mode);
    assert s = open_ok report "cannot open data/value.txt" severity failure;
    readline(f, l);
    read(l, v);
    report "DATA=" & integer'image(v);
    report "CASE PASS";
    wait;
  end process;
end architecture;
