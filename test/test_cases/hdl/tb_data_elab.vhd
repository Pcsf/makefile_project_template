-- Reads a file while the design elaborates: a constant initialised by an
-- impure function, the way a testbench reads its configuration.
use std.textio.all;

entity tb_data_elab is
end entity;

architecture sim of tb_data_elab is
  impure function read_value(name : string) return integer is
    file f     : text open read_mode is name;
    variable l : line;
    variable v : integer;
  begin
    readline(f, l);
    read(l, v);
    return v;
  end function;

  constant C_VALUE : integer := read_value("data/value.txt");
begin
  process
  begin
    report "DATA=" & integer'image(C_VALUE);
    report "CASE PASS";
    wait;
  end process;
end architecture;
