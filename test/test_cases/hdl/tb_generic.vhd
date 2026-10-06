-- Reports the generics it was elaborated with, so a run can be checked for
-- having received them.
use work.case_pkg.all;

entity tb_generic is
  generic (
    G_VALUE : integer := 0;
    G_MODE  : mode_t  := MODE_A
  );
end entity;

architecture sim of tb_generic is
begin
  process
  begin
    wait for 1 us;
    report "VALUE=" & integer'image(G_VALUE) & " MODE=" & mode_t'image(G_MODE);
    report "CASE PASS";
    wait;
  end process;
end architecture;
